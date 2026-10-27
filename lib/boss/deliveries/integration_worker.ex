defmodule Boss.Deliveries.IntegrationWorker do
  @moduledoc false
  alias Boss.{Deliveries, Repo}
  alias Boss.Deliveries.{Integration, Worker}

  def execute(delivery, repo, manager) do
    Repo.put_dynamic_repo(repo)

    result =
      try do
        perform(delivery)
      rescue
        _ -> Deliveries.interrupt(delivery.id)
      catch
        _, _ -> Deliveries.interrupt(delivery.id)
      end

    send(manager, {:delivery_finished, delivery.id, result})
  end

  defp perform(delivery) do
    {project, _} = Deliveries.inputs(delivery)
    steps = Deliveries.steps(delivery.id)
    review = steps |> Enum.reverse() |> Enum.find(&(&1.kind == "review"))
    check = Enum.find(steps, &(&1.id == review.input["check_step_id"]))

    with :ok <- continue(),
         {:ok, intent} <-
           Integration.plan(
             project,
             delivery.id,
             check.input["workspace"],
             review.input["candidate_commit"],
             delivery.intent["base_commit"]
           ),
         {:ok, _} <- Deliveries.set_integration_intent(delivery.id, intent),
         {:ok, step} <-
           Deliveries.begin_step(delivery.id, "publish", delivery.cycle, %{
             "intent" => intent,
             "review_step_id" => review.id
           }) do
      publish(delivery, step, intent)
    else
      {:error, reason} -> stop(delivery, reason)
    end
  end

  defp publish(delivery, step, intent) do
    result =
      with :ok <- continue(),
           :ok <- Integration.prepare(intent),
           :ok <- continue(),
           do:
             Integration.publish(intent,
               authorize: fn -> Deliveries.authorize_publication(delivery.id) end
             )

    case result do
      {:ok, sha} ->
        with {:ok, _} <-
               Deliveries.finish_step(step.id, %{
                 "status" => "finished",
                 "cleanup" => "group_empty",
                 "candidate_commit" => sha
               }),
             :ok <- continue(),
             {:ok, check} <-
               Deliveries.begin_step(delivery.id, "post_check", delivery.cycle, %{
                 "intent" => intent,
                 "publish_step_id" => step.id,
                 "config_hash" => delivery.config_hash
               }) do
          {receipt, _output} =
            Worker.run_check(intent["path"], delivery.check_config, fn ->
              Integration.verify_published(intent)
            end)

          receipt = Map.put(receipt, "candidate_commit", sha)

          with {:ok, _} <- Deliveries.finish_step(check.id, receipt) do
            case receipt do
              %{"status" => "finished"} ->
                with :ok <- continue(),
                     :ok <- Integration.verify_published(intent),
                     do: Deliveries.complete(delivery.id, "done")

              %{"cleanup" => "unknown"} ->
                Deliveries.interrupt(delivery.id)

              _ ->
                Deliveries.complete(
                  delivery.id,
                  "blocked",
                  "The commit was published, but post-integration checks did not pass. Target was not rolled back; inspect the retained checkout."
                )
            end
          end
        else
          {:error, reason} -> stop(delivery, reason)
        end

      {:error, reason} ->
        unknown = reason in [:cleanup_unknown, :publication_unknown, :storage_error]

        status =
          if unknown,
            do: "interrupted",
            else: if(reason == :cancelled, do: "cancelled", else: "failed")

        with {:ok, _} <-
               Deliveries.finish_step(step.id, %{
                 "status" => status,
                 "cleanup" => if(unknown, do: "unknown", else: "group_empty")
               }) do
          stop(delivery, reason)
        end
    end
  end

  defp stop(d, reason) when reason in [:cleanup_unknown, :publication_unknown, :storage_error],
    do: Deliveries.interrupt(d.id)

  defp stop(d, :cancelled),
    do:
      Deliveries.complete(
        d.id,
        "cancelled",
        "Stopped. Any published commit and all workspaces are retained."
      )

  defp stop(d, :target_checked_out),
    do:
      Deliveries.complete(
        d.id,
        "blocked",
        "Target branch is checked out in another worktree. BOSS will not change that checkout. Release the target before starting another delivery."
      )

  defp stop(d, reason) when reason in [:target_changed, :target_drift],
    do:
      Deliveries.complete(
        d.id,
        "blocked",
        "Target branch changed since this workflow started. A fresh workflow must review the new base."
      )

  defp stop(d, _),
    do:
      Deliveries.complete(
        d.id,
        "blocked",
        "Integration could not verify the saved candidate, target or ownership. Workspaces retained; no automatic retry."
      )

  defp continue do
    receive do
      :stop -> {:error, :cancelled}
    after
      0 -> :ok
    end
  end
end
