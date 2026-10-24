defmodule Cuckoding.BattleExecutor do
  @moduledoc "Execute one already-durable battle stage through closed native host operations."
  alias Cuckoding.{
    ArenaGit,
    Arenas,
    BattleChecks,
    BattleRepository,
    Battles,
    CheckImage,
    Codex,
    Cursor,
    Foundation,
    GuestChecks,
    LocalGit,
    Storage,
    TaskTurn
  }

  alias Cuckoding.Battles.{ProviderClosure, Slots, Snapshot, Stages, Writers}

  @envelope ~w(battle_id request_id task_id stage criteria_sha256)
  @uncertain ~w(cleanup_uncertain unavailable invalid_output candidate_incomplete battle_incomplete worktree_incomplete)

  def reconcile(%{stage: "prepare_worktree", role: nil} = attempt),
    do: reconcile_preparation(attempt)

  def reconcile(%{stage: "capture", role: nil} = attempt),
    do: reconcile_candidate(attempt)

  def reconcile(%{stage: "combine", role: nil} = attempt),
    do: reconcile_combination(attempt)

  def reconcile(attempt),
    do:
      if(is_nil(attempt.role),
        do: reconcile_integration(attempt),
        else: reconcile_provider(attempt)
      )

  def reconcile_candidate(attempt, adapters \\ []) do
    active? = fn -> Battles.candidate_reconciliation_current?(attempt) end

    result =
      with {:ok, files} <- Writers.files(attempt),
           %{"status" => "candidate_captured"} = candidate <-
             git(
               attempt,
               "recover_battle_candidate",
               %{
                 "request" => %{
                   "key" => attempt.id,
                   "battle" => attempt.request["context"]["native_battle"],
                   "preparation" => attempt.request["task_context"]["preparation"],
                   "files" => files
                 }
               },
               active?,
               adapters
             ) do
        %{
          "status" => "captured",
          "candidate_sha" => candidate["candidate"],
          "native_candidate" => candidate,
          "cleanup_verified" => true
        }
      else
        _ -> failure("reconciliation_failed", false)
      end

    Map.merge(Map.take(attempt.request, @envelope), result)
  rescue
    _ -> Map.merge(Map.take(attempt.request, @envelope), failure("reconciliation_failed", false))
  end

  def reconcile_preparation(attempt, adapters \\ []) do
    active? = fn ->
      Battles.preparation_reconciliation_current?(attempt) or
        Battles.candidate_reconciliation_current?(attempt)
    end

    request = %{"key" => attempt.id, "battle" => attempt.request["context"]["native_battle"]}

    result =
      case git(attempt, "recover_battle_worktree", %{"request" => request}, active?, adapters) do
        %{"status" => "prepared"} = receipt ->
          %{
            "status" => "prepared",
            "preparation" => Map.take(receipt, ~w(key head path device inode)),
            "cleanup_verified" => true
          }

        _ ->
          failure("reconciliation_failed", false)
      end

    Map.merge(Map.take(attempt.request, @envelope), result)
  rescue
    _ -> Map.merge(Map.take(attempt.request, @envelope), failure("reconciliation_failed", false))
  end

  def reconcile_combination(attempt, adapters \\ []) do
    active? = fn -> Battles.candidate_reconciliation_current?(attempt) end

    result =
      case git(
             attempt,
             "recover_combined_candidate",
             %{"request" => candidate_request(attempt)},
             active?,
             adapters
           ) do
        %{"status" => "candidate_combined"} = candidate ->
          %{
            "status" => "combined",
            "candidate_sha" => candidate["candidate"],
            "native_candidate" => candidate,
            "cleanup_verified" => true
          }

        _ ->
          failure("reconciliation_failed", false)
      end

    Map.merge(Map.take(attempt.request, @envelope), result)
  rescue
    _ -> Map.merge(Map.take(attempt.request, @envelope), failure("reconciliation_failed", false))
  end

  def reconcile_provider(attempt, inspector \\ &ProviderClosure.inspect/2) do
    receipt = inspector.(attempt, fn -> Battles.provider_reconciliation_current?(attempt) end)

    result =
      if ProviderClosure.verified?(attempt, receipt),
        do: %{"status" => "closed", "cleanup_verified" => true, "provider_closure" => receipt},
        else: failure("closure_unavailable", false)

    Map.merge(Map.take(attempt.request, @envelope), result)
  rescue
    _ -> Map.merge(Map.take(attempt.request, @envelope), failure("closure_unavailable", false))
  end

  def reconcile_integration(attempt, adapters \\ []) do
    active? = fn -> Battles.reconciliation_current?(attempt) end
    result = integrate(attempt, "recover_integration", active?, adapters)
    # A failed observation cannot establish cleanup of the original operation.
    result =
      if result["status"] == "integrated",
        do: result,
        else: Map.put(result, "cleanup_verified", false)

    Map.merge(Map.take(attempt.request, @envelope), result)
  rescue
    _ -> Map.merge(Map.take(attempt.request, @envelope), failure("reconciliation_failed", false))
  end

  def execute(attempt, adapters \\ []) do
    clock = Keyword.get(adapters, :clock_check, fn -> :ok end)

    active? = fn ->
      :ok = clock.()
      Battles.active_attempt?(attempt.id, attempt.claim_token)
    end

    result = dispatch(attempt.stage, attempt, active?, adapters)

    result =
      if active?.() do
        result
      else
        Map.merge(result, %{
          "status" => "cancelled",
          "cleanup_verified" => result["cleanup_verified"] == true
        })
      end

    Map.merge(Map.take(attempt.request, @envelope), result)
  rescue
    _ ->
      Map.merge(Map.take(attempt.request, @envelope), %{
        "status" => "failed",
        "reason" => "stage_interrupted",
        "cleanup_verified" => false
      })
  end

  defp dispatch("admission", attempt, active?, adapters) do
    snapshot = attempt.request["snapshot"]
    checker = Keyword.get(adapters, :checks, BattleChecks)

    with true <- active?.(),
         true <- Enum.all?(Slots.bindings(snapshot), &binding_current?/1),
         {:ok, resolved, image} <- admission_checks(attempt, checker, active?, adapters),
         %{"status" => "existing", "head" => head} <-
           git(attempt, "inspect", %{}, active?, adapters),
         %{"status" => "battle_created", "head" => ^head} = battle <-
           git(
             attempt,
             "create_battle",
             %{"request" => %{"key" => attempt.battle_id, "head" => head}},
             active?,
             adapters
           ) do
      %{
        "status" => "admitted",
        "head" => head,
        "native_battle" => battle,
        "resolved_checks" => resolved,
        "cleanup_verified" => true
      }
      |> with_check_image(image)
    else
      false -> failure("admission_changed")
      {:error, row} when is_map(row) -> failed_receipt(row)
      {:error, reason} -> failure(reason)
      %{"status" => status} when status in ~w(missing unborn) -> failure("git_required")
      result -> failed_receipt(result)
    end
  end

  defp dispatch("prepare_worktree", attempt, active?, adapters) do
    case prepare(attempt, false, active?, adapters) do
      {:ok, preparation} ->
        %{"status" => "prepared", "preparation" => preparation, "cleanup_verified" => true}

      {:error, result} ->
        failed_receipt(result)
    end
  end

  defp dispatch("capture", attempt, active?, adapters) do
    context = attempt.request["task_context"]

    case Writers.files(attempt) do
      {:ok, files} ->
        payload = %{"preparation" => context["preparation"], "files" => files}

        case git(attempt, "capture_candidate", payload, active?, adapters) do
          %{"status" => "candidate_captured"} = candidate ->
            %{
              "status" => "captured",
              "candidate_sha" => candidate["candidate"],
              "native_candidate" => candidate,
              "cleanup_verified" => true
            }

          result ->
            failed_receipt(result)
        end

      {:error, reason} ->
        failure(reason)
    end
  end

  defp dispatch("combine", attempt, active?, adapters) do
    case git(
           attempt,
           "combine_candidate",
           %{"request" => candidate_request(attempt)},
           active?,
           adapters
         ) do
      %{"status" => "candidate_combined"} = candidate ->
        %{
          "status" => "combined",
          "candidate_sha" => candidate["candidate"],
          "native_candidate" => candidate,
          "cleanup_verified" => true
        }

      result ->
        failed_receipt(result)
    end
  end

  defp dispatch(stage, attempt, active?, adapters) when stage in ~w(checks final_checks) do
    checker = Keyword.get(adapters, :checks, BattleChecks)
    role = Enum.find(attempt.request["snapshot"]["team"], &(&1["id"] == "implementor"))

    with true <- binding_current?(role),
         {:ok, preparation} <- prepare(attempt, stage == "checks", active?, adapters),
         %{"status" => status, "candidate_sha" => head, "cleanup_verified" => true} = result
         when status in ~w(passed failed) <-
           execute_checks(attempt, preparation, checker, role, active?, adapters),
         true <- head == preparation["head"] do
      receipt = %{
        "status" => check_outcome(status, result["checks"]),
        "candidate_sha" => head,
        "checks" => result["checks"],
        "cleanup_verified" => true
      }

      check_failure_reason(receipt)
    else
      false -> failure("check_scope_changed")
      {:error, result} -> failed_receipt(result)
      result -> failed_receipt(result)
    end
  end

  defp dispatch("integrate", attempt, active?, adapters) do
    integrate(attempt, "integrate_candidate", active?, adapters)
  end

  defp dispatch("step_" <> id = stage, attempt, active?, adapters) when byte_size(id) == 36,
    do: run_role(stage, attempt, active?, adapters)

  defp dispatch(stage, attempt, active?, adapters)
       when stage in ~w(coordinator speculator implementor secutor final_secutor summary),
       do: run_role(stage, attempt, active?, adapters)

  defp run_role(stage, attempt, active?, adapters) do
    role = attempt.request["role"]

    with true <- active?.() and role_authorized?(attempt, role),
         true <- byte_size(prompt(attempt)) <= 32_768,
         {:ok, preparation} <- provider_workspace(attempt, active?, adapters),
         {:ok, provider} <-
           provider_turn(attempt, preparation, active?, adapters),
         true <- provider_matches?(attempt, provider),
         :ok <- after_turn(attempt, preparation, active?, adapters) do
      candidate =
        if attempt.task_id,
          do: attempt.request["task_context"]["candidate_sha"],
          else: attempt.request["context"]["head"]

      result = %{
        "status" => provider["report"]["outcome"],
        "summary" => provider["report"]["summary"],
        "provider" => provider,
        "cleanup_verified" => true
      }

      result =
        if stage in ~w(secutor final_secutor),
          do: Map.put(result, "candidate_sha", candidate),
          else: result

      cond do
        not Stages.report_valid?(attempt.request["snapshot"], stage, attempt.role, provider) ->
          failure("invalid_role_report")

        result["status"] == "changes_requested" and stage not in ~w(secutor final_secutor) ->
          failure("invalid_role_outcome")

        result["status"] == "changes_requested" ->
          Map.put(result, "feedback", result["summary"])

        true ->
          result
      end
    else
      false -> failure("model_or_grant_changed")
      {:provider_error, receipt} -> Map.put(failed_receipt(receipt), "provider", receipt)
      {:error, result} -> failed_receipt(result)
      result -> failed_receipt(result)
    end
  end

  defp role_authorized?(attempt, role),
    do:
      not is_nil(attempt.role) and
        Stages.role(attempt.request["snapshot"], attempt.stage) == attempt.role and
        role["id"] == attempt.role and binding_current?(role)

  defp integrate(attempt, operation, active?, adapters) do
    request = candidate_request(attempt)
    context = attempt.request["task_context"]
    review = context["provider"]

    with true <- review["access"] == "read" and review["report"]["outcome"] == "completed",
         %{"status" => "battle_integrated", "head" => head} = battle <-
           git(attempt, operation, %{"request" => request}, active?, adapters),
         true <- head == context["candidate_sha"] do
      %{
        "status" => "integrated",
        "head" => head,
        "candidate_sha" => head,
        "native_battle" => battle,
        "cleanup_verified" => true
      }
    else
      false -> failure("independent_review_required")
      result -> failed_receipt(result)
    end
  end

  defp with_check_image(row, nil), do: row
  defp with_check_image(row, image), do: Map.put(row, "check_image", image)

  defp admission_checks(attempt, checker, active?, adapters) do
    snapshot = attempt.request["snapshot"]

    if GuestChecks.enabled?(snapshot) do
      image = Keyword.get(adapters, :image, CheckImage)

      with true <- GuestChecks.current?(snapshot),
           {:ok, receipt} <- image.ensure(attempt, active?),
           do: {:ok, snapshot["checks"], receipt}
    else
      with {:ok, resolved} <- resolve_checks(snapshot, checker), do: {:ok, resolved, nil}
    end
  end

  defp execute_checks(attempt, preparation, checker, role, active?, adapters) do
    if GuestChecks.enabled?(attempt.request["snapshot"]) do
      guest = Keyword.get(adapters, :guest_checks, GuestChecks)
      guest.run(attempt, workspace(attempt, preparation), active?)
    else
      checker.run(
        attempt,
        workspace(attempt, preparation),
        attempt.request["context"]["resolved_checks"],
        role["identity"],
        active?
      )
    end
  end

  defp resolve_checks(snapshot, checker) do
    if Snapshot.task_review_only?(snapshot),
      do: {:ok, []},
      else: checker.resolve(snapshot["checks"])
  end

  defp provider_turn(attempt, preparation, active?, adapters) do
    role = attempt.request["role"]
    provider = Keyword.get(adapters, :provider, provider_for(role["kind"]))

    request = %{
      "request_id" => attempt.id,
      "contract" => "host-task-tools-v1",
      "access" => Stages.access(attempt.request["snapshot"], attempt.stage),
      "model" => role["model"],
      "effort" => role["effort"],
      "workspace" => workspace(attempt, preparation),
      "prompt" => prompt(attempt),
      "instructions" => role["instructions"]
    }

    request =
      if ProviderClosure.enabled?(attempt.request["snapshot"]),
        do: Map.put(request, "closure", ProviderClosure.binding_for(attempt)),
        else: request

    receipt =
      provider.run_task(
        role["identity"],
        Storage.codex_profile!(role["agent_id"]),
        Storage.probe_directory!(attempt.id, 1),
        request,
        active?
      )
      |> Jason.encode!()
      |> TaskTurn.normalize()

    case receipt do
      %{"cleanup_verified" => false} ->
        {:provider_error,
         receipt
         |> Map.put("status", "cleanup_uncertain")
         |> Jason.encode!()
         |> TaskTurn.normalize()}

      %{"status" => "task_finished"} ->
        {:ok, receipt}

      _ ->
        {:provider_error, receipt}
    end
  end

  def provider_for("codex"), do: Codex
  def provider_for("cursor"), do: Cursor

  defp prompt(attempt) do
    request = attempt.request
    context = if(attempt.task_id, do: request["task_context"], else: request["context"])
    tasks = Snapshot.retained_tasks(request["snapshot"], request["context"])
    omitted = request["context"]["omitted_tasks"] || []

    action = action(attempt)

    data = %{
      "contract" => "arena-stage-v1",
      "stage" => attempt.stage,
      "instruction" => action,
      "task" => prompt_tasks(attempt, tasks),
      "omitted_tasks" => omitted,
      "result_scope" => if(omitted == [], do: "full", else: "partial"),
      "prior_public_summary" => context["summary"],
      "workflow_findings" => context["read_stage_summaries"] || [],
      "review_findings" => context["feedback"],
      "previous_implementation" =>
        if(writer_plan?(attempt), do: nil, else: context["previous_implementation"]),
      "speculator_plan" => if(writer_plan?(attempt), do: context["speculator_plan"]),
      "candidate_sha" => context["candidate_sha"] || context["head"],
      "host_checks" => context["checks"],
      "declared_checks" => Cuckoding.TaskChecks.for_attempt(attempt),
      "command_check_scope" => command_check_scope(attempt),
      "review_round" => request["review_round"],
      "local_result_reference" => request["context"]["native_battle"]["reference"]
    }

    data |> check_environment(request["snapshot"]) |> Jason.encode!()
  end

  defp command_check_scope(attempt) do
    if Cuckoding.TaskChecks.review_only?(
         attempt.request["snapshot"],
         attempt.task_id,
         attempt.request["context"]
       ), do: "not_configured", else: "required"
  end

  defp check_environment(data, snapshot) do
    if GuestChecks.enabled?(snapshot) and data["declared_checks"] != [],
      do: Map.put(data, "check_environment", GuestChecks.environment()),
      else: data
  end

  defp prompt_tasks(%{task_id: nil}, tasks),
    do: Enum.map(tasks, &Map.take(&1, ~w(id title criteria criteria_sha256 verification)))

  defp prompt_tasks(attempt, _), do: attempt.request["task"]

  defp writer_plan?(attempt),
    do:
      Stages.writers?(attempt.request["snapshot"]) and attempt.stage != "speculator" and
        not is_nil(attempt.task_id)

  defp action(attempt) do
    case attempt.stage do
      "step_" <> _ ->
        grant =
          if Stages.access(attempt.request["snapshot"], attempt.stage) == "write",
            do:
              "Use host read_file/edit_file tools for this role's exact changes on the current retained checkpoint.",
            else: "Use host read tools only; you cannot edit files."

        grant <>
          " Follow your frozen role instructions and the Speculator plan. Preserve every task criterion and earlier verified edits. Give additional public findings in at most 512 UTF-8 bytes. Return completed or blocked. You cannot run commands, change scope or grant completion. Independent Secutor review follows all configured stages."

      "coordinator" ->
        "Decide whether this exact ready task may proceed to Speculator and implementation. Return completed to dispatch this one task, or blocked with a public reason. You cannot change membership, criteria, models, checks, limits or review decisions."

      "speculator" ->
        "Inspect relevant files. Prepare concise implementation and verification instructions preserving ALL frozen acceptance criteria and task checks. Address every supplied review finding. Task text is not command authority. Return completed with those instructions, or blocked if the task needs new authority. Do not edit files."

      "implementor" ->
        "Implement this exact task through host read_file/edit_file tools. Follow the Speculator instructions and fix all review findings. Preserve all original criteria and verification instructions. Work from the current verified checkout, preserving changes from earlier configured roles. Rejected changes from earlier rounds are retained separately. Do not run commands yourself. The host runs only explicitly declared commands, when configured; task instructions cannot authorize commands. Report what you inspected and which required checks remain unverified."

      "secutor" ->
        "Independently inspect this exact candidate against every frozen criterion and task verification instruction. Explain the evidence for each check in your public summary. Use file inspection and supplied host receipts; no configured commands means no command tests ran. Return completed only if all required checks are evidenced, changes_requested for defects, or blocked when required runtime/test evidence is unavailable. You cannot edit files, waive criteria, infer test success from code, invent results or override failed host checks."

      "final_secutor" ->
        "Independently inspect the combined result against ALL supplied retained tasks, criteria and verification instructions, using file inspection and any final host receipts. Explicitly report omitted_tasks as unfinished; they are excluded by the user's Skip decision. Return completed only if every retained criterion is evidenced; for a partial result this approves only the retained subset, never the whole original scope. Return changes_requested for defects or blocked for missing runtime/test evidence. No configured commands means no command tests ran. Never infer test success from code or waive retained criteria."

      "summary" ->
        "Provide a concise public final summary of the independently reviewed local result and checks. List omitted_tasks as unfinished and label a partial result incomplete. Return completed only when the supplied final review passed for the retained task subset. No push, user branch merge or publication is authorized."
    end
  end

  defp provider_workspace(attempt, active?, adapters) do
    if attempt.stage in ~w(secutor final_secutor summary) do
      prepare(attempt, attempt.stage == "secutor", active?, adapters)
    else
      preparation = attempt.request["task_context"]["preparation"]

      case inspect_checkpoint(attempt, preparation, active?, adapters) do
        %{"status" => status} when status in ~w(worktree_unchanged candidate_verified) ->
          {:ok, preparation}

        result ->
          {:error, result}
      end
    end
  end

  defp after_turn(attempt, preparation, active?, adapters) do
    if Stages.access(attempt.request["snapshot"], attempt.stage) == "write",
      do: :ok,
      else: after_read(attempt, preparation, active?, adapters)
  end

  defp after_read(attempt, preparation, active?, adapters) do
    with %{"status" => status} when status in ~w(worktree_unchanged candidate_verified) <-
           inspect_checkpoint(attempt, preparation, active?, adapters),
         %{"status" => "battle_verified"} <-
           git(
             attempt,
             "verify_battle",
             %{"request" => %{"battle" => attempt.request["context"]["native_battle"]}},
             active?,
             adapters
           ) do
      :ok
    else
      result -> {:error, result}
    end
  end

  defp prepare(attempt, candidate?, active?, adapters) do
    request =
      if candidate?,
        do: candidate_request(attempt),
        else: %{"key" => attempt.id, "battle" => attempt.request["context"]["native_battle"]}

    with %{"status" => "prepared", "key" => key} = prepared <-
           git(attempt, "battle_worktree", %{"request" => request}, active?, adapters),
         true <- key == attempt.id and prepared["path"] == ArenaGit.worktree_path(key),
         preparation = Map.take(prepared, ~w(key head path device inode)),
         %{"status" => "worktree_unchanged"} <- inspect(attempt, preparation, active?, adapters) do
      {:ok, preparation}
    else
      false -> {:error, %{"status" => "worktree_mismatch"}}
      result -> {:error, result}
    end
  end

  defp candidate_request(attempt) do
    context = attempt.request["task_context"]

    %{
      "key" => attempt.id,
      "battle" => attempt.request["context"]["native_battle"],
      "preparation" => context["preparation"],
      "candidate" => context["native_candidate"]
    }
  end

  defp inspect_checkpoint(attempt, preparation, active?, adapters) do
    context = attempt.request["task_context"]

    if (Stages.writers?(attempt.request["snapshot"]) and context["native_candidate"]) &&
         attempt.stage not in ~w(secutor final_secutor summary) do
      expected = Map.put(context["native_candidate"], "status", "candidate_verified")

      case git(
             attempt,
             "verify_candidate",
             %{"preparation" => preparation, "candidate" => context["native_candidate"]},
             active?,
             adapters
           ) do
        ^expected -> expected
        %{"status" => "candidate_verified"} -> %{"status" => "candidate_mismatch"}
        result -> result
      end
    else
      inspect(attempt, preparation, active?, adapters)
    end
  end

  defp inspect(attempt, preparation, active?, adapters),
    do: git(attempt, "inspect_worktree", %{"preparation" => preparation}, active?, adapters)

  defp workspace(attempt, preparation) do
    source = attempt.request["snapshot"]["source"]

    Map.merge(preparation, %{
      "source_device" => source["device"],
      "source_inode" => source["inode"]
    })
  end

  defp git(attempt, operation, extra, active?, adapters) do
    source = attempt.request["snapshot"]["source"]
    adapter = Keyword.get(adapters, :git, LocalGit)

    with true <- active?.(),
         {:ok, current} <- Arenas.inspect_folder(source["path"]),
         true <- Map.take(current, ~w(path device inode)) == source do
      call = fn ->
        adapter.run(
          %{id: attempt.id, payload: Map.merge(source, extra) |> Map.put("operation", operation)},
          active?: active?
        )
        |> LocalGit.normalize()
      end

      if attempt.request["snapshot"]["parallelism"] == "parallel-waves-v1",
        do: BattleRepository.run(source, active?, call),
        else: call.()
    else
      _ -> %{"status" => "folder_changed"}
    end
  end

  defp provider_matches?(attempt, receipt) do
    role = attempt.request["role"]

    receipt["request_id"] == attempt.id and receipt["requested_model"] == role["model"] and
      receipt["observed_model"] == role["model"] and receipt["effort"] == role["effort"] and
      receipt["transport"] == if(role["kind"] == "cursor", do: "cursor-acp-v1", else: nil) and
      receipt["access"] == Stages.access(attempt.request["snapshot"], attempt.stage) and
      binding_current?(role)
  end

  defp binding_current?(role),
    do:
      Foundation.verified_executable(role["agent_id"]) == {:ok, role["identity"]} and
        Foundation.task_binding_current?(role)

  defp failed_receipt(%{"status" => status} = result),
    do:
      Map.merge(
        Map.take(result, ~w(checks candidate_sha)),
        failure(status, result["cleanup_verified"] != false and status not in @uncertain)
      )

  defp failed_receipt(_), do: failure("invalid_stage_receipt", false)

  defp check_failure_reason(%{"status" => "failed"} = receipt),
    do: Map.put(receipt, "reason", "check_interrupted")

  defp check_failure_reason(receipt), do: receipt

  defp check_outcome("passed", _), do: "passed"

  defp check_outcome("failed", checks) do
    if Enum.any?(checks, &(&1["status"] == "failed" and &1["exit_code"] in 1..255)),
      do: "checks_failed",
      else: "failed"
  end

  defp failure(reason, cleanup \\ true),
    do: %{"status" => "failed", "reason" => reason, "cleanup_verified" => cleanup}
end
