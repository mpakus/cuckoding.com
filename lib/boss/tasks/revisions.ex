defmodule Boss.Tasks.Revisions do
  @moduledoc "Explicit source adoption inside the task command's pinned transaction."

  import Ecto.Query
  alias Boss.Repo
  alias Boss.Projects.{Spec, SpecDocument, SpecRevision}
  alias Boss.Runs.Run
  alias Boss.Deliveries.Delivery

  @idle ~w(new ready failed interrupted cancelled blocked needs_input ready_to_merge)
  @runs_active ~w(preparing launching running stopping)
  @deliveries_active ~w(planning implementing testing reviewing integrating)

  def status(task, spec, pinned, target) do
    case validate(task, spec, pinned, target) do
      {:ok, _attrs} -> %{available?: true, reason: nil}
      {:error, reason} -> %{available?: false, reason: reason}
    end
  end

  def ensure_project!(task, project_id) do
    Repo.get_by(Spec, id: task.spec_id, project_id: project_id) || Repo.rollback(:not_found)
  end

  def changes(task, command) do
    spec = ensure_project!(task, command.project_id)
    pinned = Repo.get!(SpecRevision, task.spec_revision_id)
    target = Repo.get_by(SpecRevision, id: command.spec_revision_id, spec_id: spec.id)

    with {:ok, attrs} <- validate(task, spec, pinned, target) do
      Repo.update_all(
        from(d in Delivery, where: d.task_id == ^task.id and d.status == "ready_to_merge"),
        set: [
          status: "cancelled",
          reason:
            "A newer task source replaced this approval. Start a fresh workflow to verify it.",
          updated_at: DateTime.utc_now()
        ]
      )

      {:ok,
       %{
         spec_revision_id: target.id,
         title: attrs.title,
         state: "new",
         recovery_state: nil,
         attention_reason: nil
       }}
    end
  end

  defp validate(_task, _spec, _pinned, nil), do: {:error, :revision_unavailable}

  defp validate(task, spec, pinned, target) do
    cond do
      target.spec_id != task.spec_id or target.number <= pinned.number ->
        {:error, :revision_unavailable}

      task.state not in @idle ->
        {:error, :task_unavailable}

      Repo.exists?(
        from r in Run,
          where: r.task_id == ^task.id and (r.status in ^@runs_active or r.cleanup == "unknown")
      ) or
          Repo.exists?(
            from d in Delivery,
              where:
                d.task_id == ^task.id and
                    (d.status in ^@deliveries_active or d.cleanup == "unknown")
          ) ->
        {:error, :busy}

      Repo.exists?(
        from d in Delivery,
          where: d.task_id == ^task.id and d.status != "done" and d.integration_intent != ^%{}
      ) ->
        {:error, :integration_unresolved}

      true ->
        validate_source(spec, target)
    end
  end

  defp validate_source(spec, target) do
    with {:ok, attrs} <- SpecDocument.parse(target.relative_path, target.original_text),
         {:ok, parsed} <-
           Spec.changeset(spec.project_id, attrs) |> Ecto.Changeset.apply_action(:insert),
         true <- parsed.identity_key == spec.identity_key do
      {:ok, attrs}
    else
      _ -> {:error, :source_unavailable}
    end
  end
end
