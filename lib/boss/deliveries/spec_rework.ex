defmodule Boss.Deliveries.SpecRework do
  @moduledoc """
  Closed-loop specification refinement by Reviewer/Analytic when a delivery finishes
  with `changes_requested`, `needs_spec_revision`, or an unresolved clarification.

  Records an immutable new `SpecRevision`, logs the Reviewer/Analytic refinement in
  `task_entries`, and adopts the new revision so the task moves back to `Backlog`
  (`state = "new"`) for the next Autopilot loop pass.
  """
  alias Boss.{Deliveries, Projects, Repo, Tasks}
  alias Boss.Deliveries.{Delivery, Step}
  alias Boss.Projects.{Project, Repository, Spec, SpecDocument, SpecRevision}
  alias Boss.Tasks.{Entries, Revisions, Task}

  @max_spec_bytes 24_000

  @doc """
  Attempts to refine and return eligible `blocked` / `needs_input` deliveries in
  `entries` back to `Backlog` (`new`) for loop pass `pass_number`.
  Returns the list of `task_id`s that were refined and returned to `Backlog`.
  """
  def refine_settled_deliveries(project_id, entries, pass_number)
      when is_integer(project_id) and is_list(entries) and is_integer(pass_number) do
    project = Repo.get(Project, project_id)

    if is_nil(project) do
      []
    else
      entries
      |> Enum.reduce([], fn {_item, _request, delivery, _task}, acc ->
        case maybe_rework_delivery(project, delivery, pass_number) do
          {:ok, task_id} -> [task_id | acc]
          _ -> acc
        end
      end)
      |> Enum.reverse()
      |> Enum.uniq()
    end
  end

  defp maybe_rework_delivery(
         %Project{} = project,
         %Delivery{
           status: status,
           cleanup: "group_empty",
           integration_command_id: nil,
           failure_code: nil
         } = delivery,
         pass_number
       )
       when status in ~w(blocked needs_input) do
    with %Task{state: task_state} = task when task_state in ~w(blocked needs_input) <-
           Repo.get(Task, delivery.task_id),
         false <- Projects.Documentation.reference_only?(task.id),
         %Spec{} = spec <- Repo.get(Spec, task.spec_id),
         %SpecRevision{} = pinned <- Repo.get(SpecRevision, task.spec_revision_id),
         {:ok, notes} <- extract_rework_notes(delivery),
         {:ok, updated_text} <-
           build_refined_markdown(spec, pinned, task.title, notes, pass_number),
         :ok <- maybe_write_spec_file(project, spec, updated_text),
         {:ok, %{revision: new_rev}} <-
           Projects.record_spec(project.id, spec_attrs(spec, task.title, updated_text)),
         true <- Revisions.status(task, spec, pinned, new_rev).available?,
         {:ok, _event} <-
           Tasks.transition(task.id, %{
             action: "adopt_revision",
             project_id: project.id,
             spec_revision_id: new_rev.id,
             expected_version: task.state_version,
             command_id: "#{delivery.id}:spec_rework:#{pass_number}"
           }) do
      Entries.add_comment(project.id, task.id, %{
        author_role: "reviewer",
        author_agent: delivery.reviewer,
        kind: "spec_update",
        stage: "spec_rework",
        delivery_id: delivery.id,
        body:
          "Reviewer refined specification (revision #{new_rev.number}, loop #{pass_number}) and returned task to Backlog: #{notes.headline}"
      })

      {:ok, task.id}
    else
      _ -> :skip
    end
  end

  defp maybe_rework_delivery(_, _, _), do: :skip

  defp extract_rework_notes(%Delivery{} = delivery) do
    steps = Deliveries.steps(delivery.id)

    latest_review =
      steps
      |> Enum.reverse()
      |> Enum.find(&(&1.kind == "review" and &1.status == "finished"))

    latest_plan =
      steps
      |> Enum.reverse()
      |> Enum.find(&(&1.kind == "plan" and &1.status == "finished"))

    latest_resolve =
      steps
      |> Enum.reverse()
      |> Enum.find(&(&1.kind == "resolve" and &1.status == "finished"))

    cond do
      match?(%Step{}, latest_review) ->
        report = latest_review.receipt["report"] || %{}
        issues = extract_issues(report)
        failed_criteria = extract_failed_criteria(report)

        bullets =
          (issues ++ failed_criteria ++ extract_resolve_advice(latest_resolve))
          |> Enum.reject(&(&1 == ""))
          |> Enum.uniq()
          |> Enum.take(8)

        if bullets != [] do
          {:ok,
           %{
             headline: hd(bullets),
             bullets: bullets
           }}
        else
          fallback_from_reason(delivery)
        end

      match?(%Step{}, latest_plan) and
          is_binary(get_in(latest_plan.receipt, ["report", "clarification"])) ->
        question =
          latest_plan.receipt["report"]["clarification"]
          |> sanitize_line(260)

        bullets =
          ([
             "Clarified decision: choose sensible idiomatic defaults consistent with repository conventions (#{question})."
           ] ++ extract_resolve_advice(latest_resolve))
          |> Enum.uniq()
          |> Enum.take(6)

        {:ok, %{headline: question, bullets: bullets}}

      true ->
        fallback_from_reason(delivery)
    end
  end

  defp fallback_from_reason(%Delivery{reason: reason}) when is_binary(reason) and reason != "" do
    clean = sanitize_line(reason, 280)

    if clean != "" do
      {:ok,
       %{
         headline: clean,
         bullets: [
           "Address prior blocker before review: #{clean}",
           "Verify every acceptance item cleanly against the repository state without leaving untracked build artifacts."
         ]
       }}
    else
      :none
    end
  end

  defp fallback_from_reason(_), do: :none

  defp extract_issues(%{"issues" => issues}) when is_list(issues) do
    Enum.map(issues, fn
      %{"summary" => s, "action" => a} when is_binary(s) and is_binary(a) ->
        sanitize_line("#{s} — Fix: #{a}", 320)

      %{"summary" => s} when is_binary(s) ->
        sanitize_line(s, 280)

      %{"message" => m} when is_binary(m) ->
        sanitize_line(m, 280)

      text when is_binary(text) ->
        sanitize_line(text, 280)

      _ ->
        ""
    end)
  end

  defp extract_issues(_), do: []

  defp extract_failed_criteria(%{"criteria" => criteria}) when is_list(criteria) do
    criteria
    |> Enum.filter(fn
      %{"passed" => false} -> true
      %{"status" => s} when s in ["failed", "missing"] -> true
      _ -> false
    end)
    |> Enum.map(fn item ->
      crit = item["criterion"] || item["name"] || ""
      note = item["evidence"] || item["reason"] || ""

      if is_binary(crit) and crit != "" do
        suffix = if is_binary(note) and note != "", do: " (#{note})", else: ""
        sanitize_line("Unmet criterion: #{crit}#{suffix}", 300)
      else
        ""
      end
    end)
  end

  defp extract_failed_criteria(_), do: []

  defp extract_resolve_advice(%Step{receipt: %{"report" => report}}) when is_map(report) do
    steps =
      case report["steps"] do
        list when is_list(list) -> Enum.take(list, 3)
        _ -> []
      end

    Enum.map(steps, fn s ->
      if is_binary(s), do: sanitize_line("Analytic guidance: #{s}", 280), else: ""
    end)
  end

  defp extract_resolve_advice(_), do: []

  defp build_refined_markdown(spec, pinned, title, notes, pass_number) do
    explicit_id =
      case spec.identity_key do
        "id:" <> id when id != "" -> id
        _ -> nil
      end

    deps =
      case SpecDocument.parse(spec.relative_path, pinned.original_text) do
        {:ok, parsed} -> Map.get(parsed, :depends_on) || []
        _ -> []
      end

    body = strip_frontmatter(pinned.original_text, title)
    bullet_lines = Enum.map_join(notes.bullets, "\n", &("- " <> &1))

    refinement_section = """

    ## Reviewer Spec Refinement (Loop #{pass_number})
    #{bullet_lines}
    """

    id_line = if is_binary(explicit_id), do: "id: #{JSON.encode!(explicit_id)}\n", else: ""

    deps_line =
      if is_list(deps),
        do: "depends_on: #{JSON.encode!(deps)}\n",
        else: ""

    frontmatter =
      if id_line != "" or deps_line != "" do
        "---\n#{id_line}#{deps_line}---\n"
      else
        ""
      end

    full = frontmatter <> String.trim_trailing(body) <> "\n" <> refinement_section

    if byte_size(full) <= @max_spec_bytes do
      {:ok, full}
    else
      {:error, :spec_too_large}
    end
  end

  defp strip_frontmatter(text, fallback_title) when is_binary(text) do
    stripped =
      case Regex.run(~r/\A---\r?\n.*?\r?\n---\r?\n(.*)\z/s, text) do
        [_, rest] -> String.trim_leading(rest)
        _ -> text
      end

    if String.starts_with?(stripped, "# ") do
      stripped
    else
      "# #{fallback_title}\n\n" <> stripped
    end
  end

  defp spec_attrs(spec, title, text) do
    base = %{
      relative_path: spec.relative_path,
      title: title,
      original_text: text
    }

    case spec.identity_key do
      "id:" <> id when id != "" -> Map.put(base, :explicit_id, id)
      _ -> base
    end
  end

  defp maybe_write_spec_file(
         %Project{intake_mode: "specs"} = project,
         %{missing: false} = spec,
         text
       ) do
    with {:ok, specs_root} <- Repository.specs_directory(project.root_path, project.specs_path),
         full <- Path.join(specs_root, spec.relative_path),
         {:ok, %{type: :regular}} <- File.lstat(full),
         :ok <- File.write(full, text) do
      :ok
    else
      _ -> {:error, :spec_file_unavailable}
    end
  end

  defp maybe_write_spec_file(_, _, _), do: :ok

  defp sanitize_line(text, limit) when is_binary(text) do
    text
    |> String.replace(~r/[\x00-\x1F\x7F]+/u, " ")
    |> String.trim()
    |> String.slice(0, limit)
  end
end
