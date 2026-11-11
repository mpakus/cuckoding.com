defmodule Boss.Projects.Intake.Attempts do
  @moduledoc false
  import Ecto.Query
  alias Boss.{Repo, Projects.Intake}
  alias Boss.Projects.Intake.{Attempt, Request}
  @limit 9_007_199_254_740_991
  @keys ~w(status cleanup outcome exit_kind exit_code signal eof usage error_class report_bytes validation_code plan_hash)
  @validation ~w(valid report_empty report_too_large report_unavailable report_replaced invalid_encoding invalid_json invalid_shape duplicate_keys unknown_fields task_limit invalid_task_id invalid_title invalid_specification invalid_acceptance invalid_dependencies invalid_sources duplicate_task_id dependency_cycle)
  @recoverable @validation -- ~w(valid report_unavailable report_replaced)
  @outcomes ~w(exited invalid_report cancelled interrupted failed timeout timed_out output_limit unsupported codex_unavailable claude_unavailable cursor_unavailable candidate_changed target_changed cleanup_unknown)
  @errors ~w(model_unavailable auth rate_limit schema transport unknown)

  def list(id),
    do: Repo.all(from a in Attempt, where: a.request_id == ^id, order_by: a.number, limit: 3)

  def begin(id) do
    transact(fn ->
      request = Repo.get(Request, id) || Repo.rollback(:not_found)
      ensure_planning!(request)
      if request.planning_version != 1, do: Repo.rollback(:legacy_planning)
      if request.workspace == %{}, do: Repo.rollback(:invalid_intent)

      planner =
        if request.model_catalog != %{},
          do: "codex",
          else: Boss.Agents.Roles.analytic(Boss.Agents.Roles.implementer())

      unless planner != "codex" or
               Boss.Agents.ModelCatalog.validate(request.model_catalog) == :ok,
             do: Repo.rollback(:catalog_invalid)

      previous = list(id)
      last = List.last(previous)

      cond do
        last && last.status == "running" -> Repo.rollback(:attempt_running)
        length(previous) >= 3 -> Repo.rollback(:planning_attempts_exhausted)
        last && not recoverable?(last) -> Repo.rollback(:attempt_not_recoverable)
        true -> :ok
      end

      if planner == "codex" and shared_startup?(previous), do: Repo.rollback(:provider_startup)
      profile = select!(request, previous, planner)

      attempt =
        Repo.insert!(%Attempt{
          id: Ecto.UUID.generate(),
          request_id: id,
          number: length(previous) + 1,
          previous_attempt_id: last && last.id,
          source_base: request.workspace["base_commit"],
          model_profile: profile
        })

      {request, attempt, true}
    end)
  end

  def finish(id, receipt) do
    if valid_receipt?(receipt) do
      transact(fn ->
        attempt = Repo.get(Attempt, id) || Repo.rollback(:not_found)
        request = Repo.get!(Request, attempt.request_id)

        cond do
          attempt.status != "running" and attempt.receipt == receipt ->
            {request, attempt, false}

          attempt.status != "running" ->
            Repo.rollback(:immutable_receipt)

          request.status != "planning" ->
            Repo.rollback(:invalid_intent)

          true ->
            saved =
              Repo.update!(
                Ecto.Changeset.change(attempt, status: receipt["status"], receipt: receipt)
              )

            {request, saved, true}
        end
      end)
    else
      {:error, :invalid_receipt}
    end
  end

  def recoverable?(%Attempt{status: "failed", receipt: r}) do
    transport?(r) and r["error_class"] not in ~w(auth rate_limit schema transport) and
      ((r["outcome"] == "invalid_report" and r["validation_code"] in @recoverable) or
         (r["outcome"] == "exited" and
            (r["exit_code"] != 0 or r["error_class"] in ~w(model_unavailable unknown))))
  end

  def recoverable?(_), do: false

  def verified!(%Request{planning_version: 0}, _tasks), do: nil

  def verified!(request, tasks) do
    case List.last(list(request.id)) do
      %Attempt{status: "finished", source_base: base, receipt: receipt} = attempt ->
        unless base == request.workspace["base_commit"] and
                 receipt["plan_hash"] == plan_hash(tasks),
               do: Repo.rollback(:invalid_plan_evidence)

        attempt.id

      _ ->
        Repo.rollback(:invalid_plan_evidence)
    end
  end

  def plan_hash(tasks) when is_list(tasks),
    do: :crypto.hash(:sha256, Jason.encode!(canonical(tasks))) |> Base.encode16(case: :lower)

  defp canonical(value) when is_map(value),
    do: %Jason.OrderedObject{
      values: value |> Enum.sort() |> Enum.map(fn {k, v} -> {k, canonical(v)} end)
    }

  defp canonical(value) when is_list(value), do: Enum.map(value, &canonical/1)
  defp canonical(value), do: value

  def unknown?(id),
    do:
      Repo.exists?(
        from a in Attempt,
          where:
            a.request_id == ^id and
              fragment("json_extract(?, '$.cleanup')='unknown'", a.receipt)
      )

  def interrupt!(id) do
    case Repo.one(from a in Attempt, where: a.request_id == ^id and a.status == "running") do
      nil ->
        false

      attempt ->
        receipt = %{
          "status" => "interrupted",
          "cleanup" => "unknown",
          "outcome" => "interrupted",
          "exit_kind" => nil,
          "exit_code" => nil,
          "signal" => nil,
          "eof" => %{"stdout" => false, "stderr" => false},
          "usage" => %{},
          "error_class" => nil,
          "report_bytes" => nil,
          "validation_code" => nil,
          "plan_hash" => nil
        }

        Repo.update!(Ecto.Changeset.change(attempt, status: "interrupted", receipt: receipt))
        true
    end
  end

  def valid_receipt?(r) when is_map(r) do
    Enum.sort(Map.keys(r)) == Enum.sort(@keys) and
      r["status"] in ~w(finished failed cancelled interrupted) and
      r["cleanup"] in ~w(group_empty unknown not_started) and r["outcome"] in @outcomes and
      r["exit_kind"] in [nil, "exit", "signal"] and nullable_int?(r["exit_code"], 2_147_483_647) and
      (is_nil(r["signal"]) or (is_integer(r["signal"]) and r["signal"] in 1..128)) and
      is_map(r["eof"]) and Enum.sort(Map.keys(r["eof"])) == ~w(stderr stdout) and
      Enum.all?(Map.values(r["eof"]), &is_boolean/1) and usage?(r["usage"]) and
      r["error_class"] in [nil | @errors] and nullable_int?(r["report_bytes"], @limit) and
      r["validation_code"] in [nil | @validation] and
      (is_nil(r["plan_hash"]) or sha256?(r["plan_hash"])) and
      lifecycle?(r)
  end

  def valid_receipt?(_), do: false

  defp lifecycle?(%{"status" => "finished"} = r),
    do:
      transport?(r) and r["outcome"] == "exited" and r["exit_code"] == 0 and
        is_nil(r["error_class"]) and r["validation_code"] == "valid" and sha256?(r["plan_hash"]) and
        is_integer(r["report_bytes"]) and r["report_bytes"] in 1..32_768

  defp lifecycle?(%{"status" => "interrupted"} = r),
    do: r["cleanup"] == "unknown" and is_nil(r["plan_hash"])

  defp lifecycle?(r),
    do:
      r["cleanup"] in ~w(group_empty not_started) and is_nil(r["plan_hash"]) and
        r["validation_code"] != "valid"

  defp transport?(r),
    do:
      r["cleanup"] == "group_empty" and r["exit_kind"] == "exit" and
        is_integer(r["exit_code"]) and r["eof"] == %{"stdout" => true, "stderr" => true} and
        is_nil(r["signal"])

  defp nullable_int?(nil, _), do: true
  defp nullable_int?(n, max), do: is_integer(n) and n >= 0 and n <= max
  defp sha256?(s), do: is_binary(s) and Regex.match?(~r/\A[0-9a-f]{64}\z/, s)

  defp usage?(usage),
    do:
      is_map(usage) and
        Enum.all?(usage, fn {k, v} ->
          k in ~w(input_tokens cached_input_tokens output_tokens) and is_integer(v) and v >= 0 and
            v <= @limit
        end)

  defp shared_startup?(previous) do
    previous
    |> Enum.filter(fn a ->
      a.status == "failed" and transport?(a.receipt) and
        a.receipt["outcome"] == "exited" and a.receipt["error_class"] in [nil, "unknown"] and
        (a.receipt["exit_code"] != 0 or a.receipt["error_class"] == "unknown")
    end)
    |> Enum.uniq_by(& &1.model_profile["model"])
    |> length() >= 2
  end

  defp select!(_request, _previous, planner) when planner in ["claude", "cursor"] do
    %{"model" => planner, "reasoning_effort" => "high"}
  end

  defp select!(request, [], _planner) do
    request.model_catalog["primary"]
  end

  defp select!(request, previous, _planner) do
    prior_model = List.last(previous).model_profile["model"]

    unavailable =
      for a <- previous,
          a.status == "failed",
          transport?(a.receipt),
          a.receipt["outcome"] == "exited",
          a.receipt["error_class"] == "model_unavailable",
          do: a.model_profile["model"]

    Enum.find(
      request.model_catalog["fallbacks"],
      &(&1["model"] not in [prior_model | unavailable])
    ) ||
      Repo.rollback(:models_exhausted)
  end

  defp ensure_planning!(%Request{status: "planning", stop_requested: true}),
    do: Repo.rollback(:cancelled)

  defp ensure_planning!(%Request{status: "planning"}), do: :ok
  defp ensure_planning!(_), do: Repo.rollback(:invalid_intent)

  defp transact(fun) do
    nested? = Repo.in_transaction?()

    case Repo.transaction(fun, mode: :immediate) do
      {:ok, {request, attempt, changed?}} ->
        if changed? and not nested?, do: Intake.broadcast(request)
        {:ok, attempt}

      error ->
        error
    end
  rescue
    _ in [Exqlite.Error, Ecto.ConstraintError, DBConnection.ConnectionError] ->
      {:error, :storage_error}
  catch
    :exit, _ -> {:error, :storage_error}
  end
end
