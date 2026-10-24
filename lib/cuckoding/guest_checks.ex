defmodule Cuckoding.GuestChecks do
  @moduledoc "Fixed offline guest checks; no provider or task text grants execution."
  alias Cuckoding.{Arenas, BattleRepository, CheckImage, LocalGit, NativeHelper}
  @policy "isolated-guest-checks-v1"
  @tools ~w(npm mix)
  @transport_ms 375_000
  @cancel_ms 15_000
  @elapsed_limit @transport_ms + @cancel_ms + 1_000
  @binding ~w(request_id check_id input_key candidate_sha manifest_sha256 image_spec_sha256 toolchain directory)

  def image_spec, do: CheckImage.spec()

  def policy_for(checks) do
    if checks != [] and Enum.all?(checks, &(&1["executable"] in @tools)),
      do: %{"version" => @policy, "image_spec_sha256" => image_spec()}
  end

  def enabled?(%{"check_execution" => %{"version" => @policy}}), do: true
  def enabled?(_), do: false

  def current?(snapshot),
    do:
      snapshot["check_execution"] == policy_for(snapshot["checks"]) and
        declarations_valid?(snapshot["checks"])

  def declarations_valid?(checks) do
    match?({:ok, _}, Cuckoding.ProjectChecks.preview(checks)) and checks != [] and
      Enum.all?(checks, &declaration?/1) and
      Enum.sum(Enum.map(checks, & &1["timeout_seconds"])) <= 600
  end

  defp declaration?(check),
    do:
      check["executable"] in @tools and check["timeout_seconds"] in 1..300 and
        directory?(check["directory"]) and length(check["arguments"]) <= 16 and
        Enum.all?(check["arguments"], &argument?/1)

  defp directory?(value),
    do:
      byte_size(value) <= 240 and not String.contains?(value, "\\") and
        (value == "." or Enum.all?(String.split(value, "/"), &(&1 not in ["", ".", ".."])))

  defp argument?(value),
    do: byte_size(value) <= 256 and not Regex.match?(~r/[\x00-\x1f\x7f-\x9f]/u, value)

  def runtime_current?(snapshot), do: not enabled?(snapshot) or current?(snapshot)

  def mixed?(checks),
    do: Enum.any?(checks, &(&1["executable"] in @tools)) and is_nil(policy_for(checks))

  def check_digest(check) do
    :crypto.hash(:sha256, [
      Enum.map(@binding, &field(check[&1])),
      <<length(check["arguments"])::32>>,
      Enum.map(check["arguments"], &field/1),
      <<check["timeout_seconds"]::64>>
    ])
    |> Base.encode16(case: :lower)
  end

  defp field(value), do: <<byte_size(value)::32, value::binary>>

  @native_fields ~w(contract key request_id check_id input_key candidate_sha check_sha256 status cleanup_verified intent_sha256 native_state vm_closed source_unchanged stdout_bytes observed_stdout_bytes stdout_sha256 exit_code elapsed_ms native_started admission_sha256)
  @outputs ~w(source_unchanged stdout_bytes observed_stdout_bytes stdout_sha256)
  @statuses ~w(passed failed source_changed output_limit timeout cancelled launch_failed invalid_output)
  @preflight ~w(invalid_request timeout cancelled launch_failed image_changed image_incomplete image_exists unsafe_image check_input_mismatch check_input_incomplete worktree_mismatch folder_changed repository_changed repository_busy unsafe_tree tree_limit unsafe_config unsupported_layout cleanup_uncertain)

  def normalize(bytes, request) when is_binary(bytes) and byte_size(bytes) <= 8192 do
    with {:ok, row} <- Jason.decode(bytes),
         true <- is_map(row),
         true <- Map.keys(row) -- @native_fields == [],
         true <- row["contract"] == "isolated-guest-check-v1" and row["key"] == request["key"],
         true <-
           Map.take(row, ~w(request_id check_id input_key candidate_sha)) ==
             Map.take(request["check"], ~w(request_id check_id input_key candidate_sha)),
         true <- row["check_sha256"] == check_digest(request["check"]),
         true <- is_boolean(row["cleanup_verified"]) and optional_elapsed?(row),
         true <- closure?(row) do
      if row["cleanup_verified"],
        do: row,
        else:
          Map.take(row, ~w(contract key request_id check_id input_key candidate_sha check_sha256))
          |> Map.merge(%{"status" => "cleanup_uncertain", "cleanup_verified" => false})
    else
      _ -> %{"status" => "invalid_output", "cleanup_verified" => false}
    end
  end

  def normalize(_, _), do: %{"status" => "invalid_output", "cleanup_verified" => false}

  defp closure?(%{"cleanup_verified" => false}), do: true

  defp closure?(%{"native_started" => false} = row),
    do:
      row["status"] in @preflight and Cuckoding.GitPreview.hash?(row["admission_sha256"], 64) and
        not Map.has_key?(row, "vm_closed") and not Map.has_key?(row, "exit_code")

  defp closure?(row) do
    not Map.has_key?(row, "native_started") and not Map.has_key?(row, "admission_sha256") and
      row["native_state"] === 0 and row["vm_closed"] == true and
      row["status"] in @statuses and Cuckoding.GitPreview.hash?(row["intent_sha256"], 64) and
      output?(row)
  end

  defp output?(row) do
    case Enum.count(@outputs, &Map.has_key?(row, &1)) do
      0 ->
        row["status"] in ~w(timeout cancelled launch_failed invalid_output) and
          not Map.has_key?(row, "exit_code")

      4 ->
        output_fields?(row) and output_status?(row)

      _ ->
        false
    end
  end

  defp output_fields?(row) do
    is_boolean(row["source_unchanged"]) and integer?(row["stdout_bytes"], 0..65_536) and
      integer?(row["observed_stdout_bytes"], 0..67_108_864) and
      Cuckoding.GitPreview.hash?(row["stdout_sha256"], 64) and
      (not Map.has_key?(row, "exit_code") or integer?(row["exit_code"], 0..255))
  end

  defp output_status?(%{"status" => "passed"} = row),
    do: row["source_unchanged"] and row["exit_code"] === 0 and same_output?(row)

  defp output_status?(%{"status" => "failed"} = row),
    do: row["source_unchanged"] and integer?(row["exit_code"], 1..255) and same_output?(row)

  defp output_status?(%{"status" => "source_changed"} = row), do: not row["source_unchanged"]

  defp output_status?(%{"status" => "output_limit"} = row),
    do: row["stdout_bytes"] == 0 and row["observed_stdout_bytes"] > 65_536

  defp output_status?(row), do: same_output?(row)
  defp same_output?(row), do: row["stdout_bytes"] == row["observed_stdout_bytes"]

  defp optional_elapsed?(row),
    do: not Map.has_key?(row, "elapsed_ms") or integer?(row["elapsed_ms"], 0..@elapsed_limit)

  defp integer?(value, range), do: is_integer(value) and value in range

  def run(attempt, workspace, active?, native \\ &native/4) do
    image = attempt.request["context"]["check_image"]

    preparation =
      workspace |> Map.take(~w(key head path device inode)) |> Map.put("status", "prepared")

    with true <-
           current?(attempt.request["snapshot"]) and CheckImage.valid?(image, image_spec()) and
             workspace["head"] == candidate(attempt),
         true <- active?.(),
         %{"status" => "check_input_prepared"} = input <-
           native.(
             attempt,
             "prepare_check_input",
             %{"key" => attempt.id, "preparation" => preparation},
             active?
           ),
         true <-
           input["key"] == attempt.id and input["worktree_key"] == preparation["key"] and
             input["candidate_sha"] == preparation["head"] do
      result = %{
        "status" => "passed",
        "candidate_sha" => input["candidate_sha"],
        "checks" => [],
        "cleanup_verified" => true
      }

      Enum.reduce_while(
        attempt.request["snapshot"]["checks"],
        result,
        &run_one(&1, &2, attempt, preparation, input, active?, native)
      )
    else
      false ->
        %{"status" => "check_scope_changed", "cleanup_verified" => true}

      row when is_map(row) ->
        %{
          "status" => "check_input_unavailable",
          "cleanup_verified" => row["cleanup_verified"] == true
        }
    end
  end

  defp run_one(check, result, attempt, preparation, input, active?, native) do
    request = request(attempt, check, preparation, input)
    receipt = native.(attempt, "run_guest_check", request, active?)
    outcome(normalize(Jason.encode!(receipt), request), receipt, result, request)
  end

  defp request(attempt, check, preparation, input) do
    image = attempt.request["context"]["check_image"]

    %{
      "contract" => "isolated-guest-check-v1",
      "key" => attempt.request["guest_check_runs"][check["id"]],
      "deadline_unix_ms" =>
        min(
          DateTime.to_unix(attempt.deadline_at, :millisecond),
          System.system_time(:millisecond) + 360_000
        ),
      "image" => %{"key" => image["key"], "image" => image},
      "input" => %{
        "key" => input["key"],
        "preparation" => preparation,
        "input" => Map.delete(input, "elapsed_ms")
      },
      "check" => check_request(attempt, check, input["manifest_sha256"])
    }
  end

  defp outcome(%{"status" => "passed", "cleanup_verified" => true} = row, _, result, request),
    do: {:cont, append(result, project(row, request))}

  defp outcome(%{"status" => "failed", "cleanup_verified" => true} = row, _, result, request),
    do: {:halt, append(result, project(row, request)) |> Map.put("status", "failed")}

  defp outcome(rejected, receipt, result, request) do
    no_launch = receipt == %{"status" => "not_started", "cleanup_verified" => true}

    public =
      if rejected["check_id"],
        do: project(rejected, request),
        else: %{
          "id" => request["check"]["check_id"],
          "status" => if(no_launch, do: "not_started", else: rejected["status"]),
          "cleanup_verified" => no_launch
        }

    clean = rejected["cleanup_verified"] == true or no_launch

    {:halt,
     append(result, public)
     |> Map.merge(%{
       "status" => "failed",
       "reason" => "guest_check_interrupted",
       "cleanup_verified" => clean
     })}
  end

  defp append(result, row), do: Map.put(result, "checks", result["checks"] ++ [row])

  defp candidate(attempt),
    do:
      if(attempt.task_id,
        do: attempt.request["task_context"]["candidate_sha"],
        else: attempt.request["context"]["head"]
      )

  defp check_request(attempt, check, manifest) do
    candidate = candidate(attempt)

    %{
      "request_id" => attempt.id,
      "check_id" => check["id"],
      "input_key" => attempt.id,
      "candidate_sha" => candidate,
      "manifest_sha256" => manifest,
      "image_spec_sha256" => attempt.request["snapshot"]["check_execution"]["image_spec_sha256"],
      "toolchain" => check["executable"],
      "directory" => check["directory"],
      "arguments" => check["arguments"],
      "timeout_seconds" => check["timeout_seconds"]
    }
  end

  defp project(row, request) do
    row
    |> Map.drop(~w(check_id))
    |> Map.put("id", row["check_id"])
    |> Map.merge(%{
      "input_manifest_sha256" => request["check"]["manifest_sha256"],
      "image_spec_sha256" => request["check"]["image_spec_sha256"],
      "image_key" => request["image"]["key"]
    })
  end

  def valid_check?(attempt, row) when is_map(row) do
    snapshot = attempt.request["snapshot"]
    declared = Enum.find(snapshot["checks"], &(&1["id"] == row["id"]))

    if (declared && byte_size(Jason.encode!(row)) <= 2048) and
         Map.keys(row) --
           ((@native_fields -- ["check_id"]) ++
              ~w(id input_manifest_sha256 image_spec_sha256 image_key)) == [] and
         Cuckoding.GitPreview.hash?(row["input_manifest_sha256"], 64) and
         row["image_key"] == attempt.request["context"]["check_image"]["key"] and
         row["image_spec_sha256"] == snapshot["check_execution"]["image_spec_sha256"] do
      raw =
        row
        |> Map.drop(~w(id input_manifest_sha256 image_spec_sha256 image_key))
        |> Map.put("check_id", row["id"])

      request = %{
        "key" => attempt.request["guest_check_runs"][row["id"]],
        "check" => check_request(attempt, declared, row["input_manifest_sha256"])
      }

      raw["cleanup_verified"] == true and raw["vm_closed"] == true and
        normalize(Jason.encode!(raw), request) == raw
    else
      false
    end
  end

  def valid_check?(_, _), do: false

  defp native(attempt, operation, request, active?) do
    source = attempt.request["snapshot"]["source"]

    result =
      with true <- active?.(),
           {:ok, current} <- Arenas.inspect_folder(source["path"]),
           true <- Map.take(current, ~w(path device inode)) == source do
        BattleRepository.run(source, active?, fn ->
          invoke(attempt, operation, request, source, active?)
        end)
      else
        _ -> %{"status" => "cancelled", "cleanup_verified" => true}
      end

    if operation == "run_guest_check", do: no_launch(result), else: result
  end

  defp invoke(attempt, "prepare_check_input", request, source, active?) do
    LocalGit.run(
      %{
        id: attempt.id,
        payload: Map.merge(source, %{"operation" => "prepare_check_input", "request" => request})
      },
      active?: active?
    )
  end

  defp invoke(attempt, "run_guest_check", request, source, active?) do
    home = Path.join(Application.fetch_env!(:cuckoding, :data_dir), "runtime-home")

    NativeHelper.request(
      attempt,
      [
        "--arena-git",
        "run_guest_check",
        source["path"],
        to_string(source["device"]),
        to_string(source["inode"]),
        home,
        Jason.encode!(request)
      ],
      @transport_ms,
      &normalize(&1, request),
      8192,
      active?: active?,
      cancel_grace: @cancel_ms
    )
  end

  # Only the host's before-launch/queue paths return this unbound acknowledgement.
  # Native replies must first pass the exact decoder and cannot impersonate it.
  defp no_launch(%{"status" => status, "cleanup_verified" => true} = row)
       when status in ~w(cancelled repository_busy) do
    if Map.drop(row, ~w(elapsed_ms)) == %{"status" => status, "cleanup_verified" => true},
      do: %{"status" => "not_started", "cleanup_verified" => true},
      else: row
  end

  defp no_launch(row), do: row
end
