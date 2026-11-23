defmodule Boss.Projects.BriefAcceptance do
  @moduledoc "Binds final project acceptance to the original committed brief and the published application."
  alias Boss.{Projects, Repo}
  alias Boss.Agents.Workspace
  alias Boss.Deliveries.Protocol

  @title "Verify the complete project brief"

  # Called in the same immediate transaction as the generated tasks and batch.
  def append!(request, %{documents: docs}, tasks, ids, namespace) do
    if criteria(docs) == [], do: Repo.rollback(:empty_brief)
    deps = Enum.map(tasks, &(namespace <> &1["id"]))
    id = "brief:" <> request.id

    sources =
      docs
      |> Enum.sort()
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {{path, text}, i} -> "## S#{i} — #{path}\n\n" <> text end)

    text = """
    ---
    id: #{JSON.encode!(id)}
    depends_on: #{JSON.encode!(deps)}
    ---
    # #{@title}

    Verify every requirement below against the finished application. Repair any missing
    behavior and retain the original requirements. The final reviewer must account for
    every supplied source range using evidence from this candidate and its actual checks.

    #{sources}
    """

    attrs = %{
      relative_path: "autopilot/brief/#{request.id}.md",
      title: @title,
      explicit_id: id,
      original_text: text
    }

    case Projects.record_spec(request.project_id, attrs) do
      {:ok, %{change: :created, revision: revision, task: task}} ->
        Repo.query!(
          "INSERT INTO project_brief_tasks (task_id,intake_id,source_revision_id,documents) VALUES (?,?,?,?)",
          [task.id, request.id, revision.id, JSON.encode!(docs)]
        )

        ids ++ [task.id]

      _ ->
        Repo.rollback(:invalid_plan)
    end
  end

  def get(task_id) do
    if installed?() do
      case Repo.query!(
             """
             SELECT b.intake_id,b.source_revision_id,b.documents,
                    json_extract(i.workspace,'$.base_commit'),i.config_hash,i.reviewer
             FROM project_brief_tasks b JOIN project_intakes i ON i.id=b.intake_id
             WHERE b.task_id=?
             """,
             [task_id]
           ).rows do
        [[id, revision, docs, base, hash, reviewer]] ->
          %{
            intake_id: id,
            source_revision_id: revision,
            documents: JSON.decode!(docs),
            base_commit: base,
            config_hash: hash,
            reviewer: reviewer
          }

        [] ->
          nil
      end
    end
  end

  def validate_replan(request_id, documents, workspace, opts) do
    if installed?() do
      case Repo.query!(
             """
             SELECT json_extract(r.start_policy,'$.previous_intake_id'), b.documents,
                    json_extract(d.integration_intent,'$.candidate_commit')
             FROM project_intakes r
             LEFT JOIN project_brief_tasks b ON b.intake_id=json_extract(r.start_policy,'$.previous_intake_id')
             LEFT JOIN deliveries d ON d.project_id=r.project_id AND d.task_id=b.task_id
               AND d.spec_revision_id=b.source_revision_id AND d.status='done' AND d.cleanup='group_empty'
             WHERE r.id=?
             """,
             [request_id]
           ).rows do
        [[nil, nil, nil]] ->
          :ok

        [[_previous, docs, sha]] when is_binary(sha) ->
          if JSON.decode!(docs) == documents do
            {:error, :brief_unchanged}
          else
            case Workspace.git(
                   workspace.repo_path,
                   ["merge-base", "--is-ancestor", sha, workspace.base_commit],
                   opts
                 ) do
              {:ok, _} -> :ok
              {:error, {:git_exit, _}} -> {:error, :brief_target_rewritten}
              error -> error
            end
          end

        _ ->
          {:error, :replan_unavailable}
      end
    else
      :ok
    end
  end

  # Historical fixture databases predate whole-brief acceptance.
  defp installed?,
    do:
      Repo.query!("SELECT 1 FROM sqlite_schema WHERE type='table' AND name='project_brief_tasks'").rows ==
        [[1]]

  def criteria(docs) do
    lines =
      docs
      |> Enum.sort()
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {{_path, text}, i} ->
        for {line, n} <- Enum.with_index(String.split(text, "\n"), 1),
            String.trim(line) != "",
            do: "S#{i}:L#{n}"
      end)

    # The existing review contract supports twenty findings. Each range includes
    # every original line between its endpoints, including across source files.
    lines
    |> Enum.chunk_every(max(1, ceil(length(lines) / 20)))
    |> Enum.map(fn
      [single] -> single
      [first | rest] -> first <> ".." <> List.last(rest)
    end)
  end

  def plan_input(input, nil), do: input

  def plan_input(input, brief) do
    Map.merge(input, %{
      "brief_criteria" => criteria(brief.documents),
      "brief_documents" => brief.documents,
      "brief_base_commit" => brief.base_commit
    })
  end

  def decode_plan(text, previous, input) do
    with {:ok, plan} <- Protocol.plan(text, previous) do
      if Map.has_key?(input, "brief_criteria") and
           not (plan["acceptance"] == [] and is_binary(plan["clarification"])) and
           MapSet.new(plan["acceptance"]) != MapSet.new(input["brief_criteria"]),
         do: {:error, :invalid_plan},
         else: {:ok, plan}
    end
  end

  def review_input(input, nil, _path), do: {:ok, input}

  def review_input(input, brief, path) do
    sha = input["candidate_commit"]

    with {:ok, _} <- Workspace.git(path, ["merge-base", "--is-ancestor", brief.base_commit, sha]),
         {:ok, diff} <-
           Workspace.git(path, [
             "diff",
             "--no-ext-diff",
             "--no-textconv",
             "--binary",
             "--full-index",
             brief.base_commit,
             sha,
             "--"
           ]),
         true <- String.valid?(diff) do
      {:ok, input |> plan_input(brief) |> Map.put("brief_diff", diff)}
    else
      false -> {:error, :invalid_input}
      error -> error
    end
  end

  def evidence(input) do
    if input["brief_criteria"] do
      %{
        "brief_base_commit" => input["brief_base_commit"],
        "brief_documents_hash" => documents_digest(input["brief_documents"]),
        "brief_diff_hash" => Protocol.digest(input["brief_diff"])
      }
    else
      %{}
    end
  end

  defp documents_digest(docs) do
    docs |> Enum.sort() |> Enum.map(fn {path, text} -> [path, text] end) |> Protocol.digest()
  end

  def ensure_approval!(delivery, review, criteria) do
    if brief = get(delivery.task_id) do
      unless brief.config_hash == delivery.config_hash and
               brief.source_revision_id == delivery.spec_revision_id and
               brief.reviewer == delivery.reviewer and
               review.input["brief_base_commit"] == brief.base_commit and
               review.input["brief_documents_hash"] == documents_digest(brief.documents) and
               match?(<<_::binary-size(64)>>, review.input["brief_diff_hash"]) and
               MapSet.new(criteria) == MapSet.new(criteria(brief.documents)),
             do: Repo.rollback(:missing_evidence)
    end
  end
end
