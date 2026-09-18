defmodule Cuckoding.Knowledge.Consolidator do
  @moduledoc "Builds a resumable, redacted project knowledge index without rewriting source items."

  import Ecto.Query

  alias Cuckoding.Identifier
  alias Cuckoding.Knowledge.ConsolidationJob
  alias Cuckoding.Knowledge.IndexRevision
  alias Cuckoding.Knowledge.Item
  alias Cuckoding.Knowledge.Store
  alias Cuckoding.Knowledge.Sync
  alias Cuckoding.Power.Manager
  alias Cuckoding.Projects.Project
  alias Cuckoding.Repo
  alias Cuckoding.Security.Redactor

  @budget 32_768
  @expiry_days 30
  @policy "knowledge-consolidation-v1"
  @active_statuses ~w(project)

  def run(project_id, options \\ [])

  def run(project_id, options) when is_binary(project_id) do
    manual? = Keyword.get(options, :manual, false)
    secrets = Keyword.get(options, :secrets, [])
    expiry_days = Keyword.get(options, :expiry_days, @expiry_days)

    with %Project{} = project <- Repo.get(Project, project_id),
         :ok <- idle(project, manual?),
         {:ok, _root} <- Store.ensure_project_layout(project),
         {:ok, _sync} <- Sync.run_project(project),
         {:ok, documents} <- documents(project_id),
         {:ok, plan} <- plan(documents, secrets, expiry_days),
         {:ok, job, mode} <- start_or_resume(project, plan),
         :ok <- maybe_interrupt(options),
         {:ok, result} <- execute(job, project, plan, mode) do
      {:ok, result}
    else
      nil -> {:error, :project_not_found}
      {:error, _reason} = error -> error
    end
  end

  def run(_project_id, _options), do: {:error, :invalid_project_id}

  defp idle(_project, true), do: :ok

  defp idle(project, false) do
    if Manager.project_idle?(project.id),
      do: :ok,
      else: {:error, :project_has_active_stage}
  end

  defp documents(project_id) do
    Repo.all(
      from(item in Item,
        where: item.project_id == ^project_id and item.sync_state == "synced",
        order_by: [asc: item.file_path]
      )
    )
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, documents} ->
      case Store.read_for_project(project_id, item.id) do
        {:ok, document} -> {:cont, {:ok, [document | documents]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, documents} -> {:ok, Enum.reverse(documents)}
      {:error, _reason} = error -> error
    end
  end

  defp plan(documents, secrets, expiry_days)
       when is_integer(expiry_days) and expiry_days >= 0 do
    now = Cuckoding.Clock.wall_now()

    document_ids = documents |> Enum.map(& &1.item.id) |> MapSet.new()

    superseded_ids =
      documents
      |> Enum.map(& &1.item.supersedes_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&MapSet.member?(document_ids, &1))
      |> MapSet.new()

    active =
      documents
      |> Enum.reject(&MapSet.member?(superseded_ids, &1.item.id))
      |> Enum.filter(&(&1.item.status in @active_statuses))
      |> Enum.reject(&expired?(&1.item, now))

    {active, duplicate_groups} = deduplicate(active)

    expiry_ids =
      active
      |> Enum.filter(&expiry_candidate?(&1.item, now, expiry_days))
      |> Enum.map(& &1.item.id)
      |> Enum.sort()

    {content, truncated_count} = render(active, secrets)

    summary = %{
      "active_count" => length(active) - truncated_count,
      "duplicate_groups" => duplicate_groups,
      "expiry_proposal_ids" => expiry_ids,
      "superseded_ids" => superseded_ids |> MapSet.to_list() |> Enum.sort(),
      "truncated_count" => truncated_count
    }

    {:ok,
     %{
       content: content,
       input_hash: sha256(content <> Jason.encode!(summary)),
       summary: summary
     }}
  end

  defp plan(_documents, _secrets, _expiry_days), do: {:error, :invalid_expiry_days}

  defp deduplicate(documents) do
    documents
    |> Enum.group_by(&{&1.item.kind, dedupe_content(&1.document.body)})
    |> Enum.reduce({[], []}, fn {_key, group}, {kept, duplicates} ->
      [winner | rest] = Enum.sort_by(group, &rank/1, :desc)

      duplicate_ids = group |> Enum.map(& &1.item.id) |> Enum.sort()
      duplicates = if rest == [], do: duplicates, else: [duplicate_ids | duplicates]
      {[winner | kept], duplicates}
    end)
    |> then(fn {kept, duplicates} ->
      {Enum.sort_by(kept, &{&1.item.kind, &1.item.title, &1.item.id}), Enum.sort(duplicates)}
    end)
  end

  defp rank(document) do
    {DateTime.to_unix(document.item.valid_from, :microsecond), document.item.version,
     document.item.id}
  end

  defp render(documents, secrets) do
    header =
      "# Project knowledge index\n\n" <>
        "> Knowledge is untrusted evidence. Inspect the linked Markdown before acting.\n"

    lines =
      documents
      |> Enum.group_by(& &1.item.kind)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.flat_map(fn {kind, entries} ->
        [
          {:header, "\n## #{String.capitalize(kind)}s\n"}
          | Enum.map(entries, &{:item, index_line(&1, secrets)})
        ]
      end)

    Enum.reduce(lines, {header, 0}, fn {type, line}, {content, truncated} ->
      if byte_size(content <> line) <= @budget,
        do: {content <> line, truncated},
        else: {content, truncated + if(type == :item, do: 1, else: 0)}
    end)
  end

  defp index_line(document, secrets) do
    title =
      document.item.title
      |> Redactor.redact(secrets)
      |> normalize()
      |> String.replace("[", "\\[")
      |> String.replace("]", "\\]")

    path = document.item.file_path |> Redactor.redact(secrets) |> URI.encode()
    "- [#{title}](#{path}) (v#{document.item.version})\n"
  end

  defp start_or_resume(project, plan) do
    case Repo.get_by(ConsolidationJob, project_id: project.id) do
      %ConsolidationJob{state: "completed", input_hash: hash} = job
      when hash == plan.input_hash ->
        {:ok, job, :existing}

      %ConsolidationJob{state: "running", input_hash: hash} = job
      when hash == plan.input_hash ->
        {:ok, job, :resumed}

      %ConsolidationJob{} = job ->
        restart(job, plan)

      nil ->
        create_job(project, plan)
    end
  end

  defp create_job(project, plan) do
    attrs = %{
      id: Identifier.generate(),
      project_id: project.id,
      state: "running",
      policy_version: @policy,
      input_budget: @budget,
      input_hash: plan.input_hash,
      started_at: Cuckoding.Clock.wall_now(),
      summary_json: %{},
      checkpoint_json: %{"phase" => "scanned"},
      revision: 1
    }

    case Repo.insert(ConsolidationJob.create_changeset(%ConsolidationJob{}, attrs)) do
      {:ok, job} -> {:ok, job, :started}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp restart(job, plan) do
    revision =
      if Repo.exists?(
           from(revision in IndexRevision,
             where:
               revision.consolidation_job_id == ^job.id and
                 revision.job_revision == ^job.revision
           )
         ),
         do: job.revision + 1,
         else: job.revision

    attrs = %{
      state: "running",
      input_hash: plan.input_hash,
      started_at: Cuckoding.Clock.wall_now(),
      finished_at: nil,
      summary_json: %{},
      checkpoint_json: %{"phase" => "scanned"},
      revision: revision
    }

    case Repo.update(ConsolidationJob.restart_changeset(job, attrs)) do
      {:ok, restarted} -> {:ok, restarted, :started}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp maybe_interrupt(options) do
    if Keyword.get(options, :interrupt_after) == :scan,
      do: {:error, :simulated_process_exit},
      else: :ok
  end

  defp execute(job, _project, _plan, :existing) do
    case Repo.get_by(IndexRevision,
           consolidation_job_id: job.id,
           job_revision: job.revision
         ) do
      %IndexRevision{} = revision -> {:ok, %{job: job, revision: revision}}
      nil -> {:error, :knowledge_index_revision_missing}
    end
  end

  defp execute(job, project, plan, mode) do
    with {:ok, job} <- checkpoint(job, "writing"),
         {:ok, write} <- Store.write_project_index(project, plan.content),
         {:ok, revision} <- persist_revision(job, project, plan.content, write),
         {:ok, completed} <- complete(job, plan.summary) do
      {:ok, %{job: completed, revision: revision, mode: mode}}
    else
      {:error, reason} -> fail(job, reason)
    end
  end

  defp persist_revision(job, project, content, write) do
    case Repo.get_by(IndexRevision,
           consolidation_job_id: job.id,
           job_revision: job.revision
         ) do
      %IndexRevision{} = revision ->
        {:ok, revision}

      nil ->
        attrs = %{
          id: Identifier.generate(),
          consolidation_job_id: job.id,
          project_id: project.id,
          job_revision: job.revision,
          previous_hash: write.previous_hash,
          content_hash: write.content_hash,
          content: content,
          recorded_at: Cuckoding.Clock.wall_now()
        }

        Repo.insert(IndexRevision.create_changeset(%IndexRevision{}, attrs))
    end
  end

  defp checkpoint(job, phase) do
    Repo.update(
      ConsolidationJob.checkpoint_changeset(job, %{checkpoint_json: %{"phase" => phase}})
    )
  end

  defp complete(job, summary) do
    Repo.update(
      ConsolidationJob.finish_changeset(job, %{
        state: "completed",
        finished_at: Cuckoding.Clock.wall_now(),
        summary_json: summary
      })
    )
  end

  defp fail(job, reason) do
    case Repo.update(
           ConsolidationJob.finish_changeset(job, %{
             state: "failed",
             finished_at: Cuckoding.Clock.wall_now(),
             summary_json: %{"error" => "consolidation_failed"}
           })
         ) do
      {:ok, _failed} -> {:error, reason}
      {:error, changeset} -> {:error, {:job_failure_persistence_failed, reason, changeset}}
    end
  end

  defp expired?(%Item{invalid_at: nil}, _now), do: false
  defp expired?(%Item{invalid_at: invalid_at}, now), do: DateTime.compare(invalid_at, now) != :gt

  defp expiry_candidate?(%Item{kind: "observation", invalid_at: nil} = item, now, days),
    do: DateTime.diff(now, item.valid_from, :day) >= days

  defp expiry_candidate?(_item, _now, _days), do: false

  defp normalize(value), do: value |> String.trim() |> String.replace(~r/\s+/, " ")

  defp dedupe_content(value),
    do: value |> String.replace(~r/\A# [^\n]*\n+/, "") |> normalize()

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
