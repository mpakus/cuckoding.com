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
  alias Boss.Projects.{BriefAcceptance, Project, Spec, SpecDocument, SpecImporter, SpecRevision}
  alias Boss.Tasks.{Entries, Event, Revisions, Task}

  @max_spec_bytes 24_000

  @doc """
  Attempts to refine and return eligible `blocked` / `needs_input` deliveries in
  `entries` back to `Backlog` (`new`) for loop pass `pass_number`.
  Returns the list of `task_id`s that were refined and returned to `Backlog`.
  """
  def refine_settled_deliveries(project_id, entries, pass_number)
      when is_integer(project_id) and is_list(entries) and is_integer(pass_number) do
    run = fn ->
      project = Repo.get(Project, project_id)

      for {_item, _request, %Delivery{id: id}, _task} <- entries,
          %Delivery{} = delivery <- [Repo.get_by(Delivery, id: id, project_id: project_id)],
          {:ok, task_id} <- [maybe_rework_delivery(project, delivery, pass_number)],
          uniq: true,
          do: task_id
    end

    if Repo.in_transaction?() do
      run.()
    else
      case Repo.transaction(run, mode: :immediate) do
        {:ok, reworked} -> reworked
        {:error, _reason} = error -> error
      end
    end
  end

  defp maybe_rework_delivery(
         %Project{} = project,
         %Delivery{
           status: status,
           cleanup: "group_empty",
           integration_command_id: nil,
           failure_code: nil,
           spec_revision_id: pin_id
         } = delivery,
         pass_number
       )
       when status in ~w(blocked needs_input) do
    with %Task{state: ^status, spec_revision_id: ^pin_id} = task <-
           Repo.get(Task, delivery.task_id),
         nil <- BriefAcceptance.get(task.id),
         %Event{} <-
           Repo.get_by(Event,
             task_id: task.id,
             version: task.state_version,
             command_id: "#{delivery.id}:complete:#{status}",
             spec_revision_id: pin_id
           ),
         %Spec{missing: false} = spec <- Repo.get(Spec, task.spec_id),
         %SpecRevision{id: ^pin_id} = pinned <- SpecRevision.latest(spec.id),
         {:ok, source} <- source_for_rework(project, pinned),
         {:ok, notes} <- extract_rework_notes(delivery),
         {:ok, updated_text} <- build_refined_markdown(project, spec, pinned, notes, pass_number),
         target = %{pinned | number: pinned.number + 1, original_text: updated_text},
         %{available?: true} <- Revisions.status(task, spec, pinned, target) do
      %{revision: revision} =
        persist!(Projects.record_spec(project.id, spec_attrs(spec, task.title, updated_text)))

      if source do
        {1, _} =
          Repo.insert_all("spec_rework_revisions", [
            %{revision_id: revision.id, source_revision_id: source.id}
          ])
      end

      persist!(
        Tasks.transition(task.id, %{
          action: "adopt_revision",
          project_id: project.id,
          spec_revision_id: revision.id,
          expected_version: task.state_version,
          command_id: "#{delivery.id}:spec_rework:#{pass_number}"
        })
      )

      persist!(
        Entries.add_comment(project.id, task.id, %{
          author_role: "reviewer",
          agent_id: delivery.reviewer,
          kind: "spec_update",
          stage: "spec_rework",
          delivery_id: delivery.id,
          spec_revision_id: revision.id,
          body:
            "Reviewer refined specification (revision #{revision.number}, loop #{pass_number}) and returned task to Backlog: #{notes.headline}"
        })
      )

      {:ok, task.id}
    else
      _ -> :skip
    end
  end

  defp maybe_rework_delivery(_, _, _), do: :skip

  defp persist!({:ok, value}), do: value
  defp persist!({:error, _reason}), do: Repo.rollback(:spec_rework_failed)

  defp source_for_rework(%Project{intake_mode: "documentation"}, _pinned), do: {:ok, nil}

  defp source_for_rework(project, pinned) do
    source = SpecRevision.file_source(pinned)
    if SpecImporter.current_file?(project, source), do: {:ok, source}, else: :skip
  end

  defp extract_rework_notes(%Delivery{} = delivery) do
    steps = Deliveries.steps(delivery.id)

    case List.last(steps) do
      %Step{kind: "resolve", status: "finished", receipt: %{"report" => report}} = resolver ->
        case report do
          %{"external_action" => nil, "steps" => advice} when is_list(advice) ->
            source = Enum.find(steps, &(&1.id == resolver.input["source_step_id"]))

            notes(
              stage_notes(source) ++ Enum.map(advice, &("Analytic guidance: " <> &1)),
              delivery
            )

          _ ->
            :none
        end

      terminal ->
        notes(stage_notes(terminal), delivery)
    end
  end

  defp stage_notes(%Step{
         kind: "review",
         status: "finished",
         receipt: %{
           "report" => %{"verdict" => verdict, "acceptance" => acceptance, "issues" => issues}
         }
       })
       when verdict in ["changes_requested", "needs_spec_revision"] do
    messages = Enum.group_by(issues, & &1["criterion"], & &1["message"])

    for %{"status" => status, "criterion" => criterion, "evidence" => evidence} <- acceptance,
        status in ["failed", "unclear"] do
      Enum.join(
        ["#{status}: #{criterion}", "Evidence: #{evidence}" | Map.get(messages, criterion, [])],
        " — "
      )
    end
  end

  defp stage_notes(%Step{
         kind: "plan",
         status: "finished",
         receipt: %{"report" => %{"clarification" => question}}
       })
       when is_binary(question),
       do: ["Planner question: #{question}"]

  defp stage_notes(_), do: []

  defp notes([], delivery), do: fallback_from_reason(delivery)

  defp notes(bullets, _delivery) do
    bullets = Enum.map(bullets, &sanitize_line/1)
    {:ok, %{headline: String.slice(hd(bullets), 0, 260), bullets: bullets}}
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

  defp build_refined_markdown(project, spec, pinned, notes, pass_number) do
    source = source_with_identity(project, spec, pinned.original_text)
    bullets = Enum.map_join(notes.bullets, "\n", &("- " <> &1))
    full = source <> "\n\n## Reviewer Spec Refinement (Loop #{pass_number})\n" <> bullets <> "\n"

    if byte_size(full) <= @max_spec_bytes, do: {:ok, full}, else: {:error, :spec_too_large}
  end

  # Intake originally assigned generated task IDs outside their Markdown.
  defp source_with_identity(
         %Project{intake_mode: "documentation"},
         %Spec{identity_key: "id:" <> id} = spec,
         text
       ) do
    case SpecDocument.parse(spec.relative_path, text) do
      {:ok, attrs} when not is_map_key(attrs, :explicit_id) ->
        id_line = "id: #{JSON.encode!(id)}\n"

        case Regex.run(~r/\A(?:\x{FEFF})?---[ \t]*\r?\n/u, text) do
          [opening] -> opening <> id_line <> String.replace_prefix(text, opening, "")
          nil -> "---\n" <> id_line <> "---\n" <> text
        end

      _ ->
        text
    end
  end

  defp source_with_identity(_project, _spec, text), do: text

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

  defp sanitize_line(text, limit), do: text |> sanitize_line() |> String.slice(0, limit)

  defp sanitize_line(text) when is_binary(text) do
    text
    |> String.replace(~r/[\x00-\x1F\x7F]+/u, " ")
    |> String.trim()
  end
end
