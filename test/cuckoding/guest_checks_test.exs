defmodule Cuckoding.GuestChecksTest do
  use ExUnit.Case, async: true
  alias Cuckoding.GuestChecks

  defp check(executable),
    do: %{
      "id" => Ecto.UUID.generate(),
      "name" => "Tests",
      "executable" => executable,
      "arguments" => ["test"],
      "directory" => ".",
      "timeout_seconds" => 30
    }

  test "only explicit npm/Mix scopes freeze the compiled guest policy" do
    policy = GuestChecks.policy_for([check("npm"), check("mix")])
    assert policy["version"] == "isolated-guest-checks-v1"
    assert policy["image_spec_sha256"] == GuestChecks.image_spec()
    assert byte_size(policy["image_spec_sha256"]) == 64
    assert GuestChecks.enabled?(%{"check_execution" => policy})
    refute GuestChecks.enabled?(%{})
    assert GuestChecks.policy_for([]) == nil
    assert GuestChecks.policy_for([check("true")]) == nil
    assert GuestChecks.mixed?([check("true"), check("npm")])
    refute GuestChecks.mixed?([check("npm"), check("mix")])
  end

  test "invalid guest declarations refuse before image or provider work" do
    base = check("npm")
    assert GuestChecks.declarations_valid?([base])

    for {key, value} <- [
          {"arguments", [String.duplicate("x", 257)]},
          {"arguments", List.duplicate("x", 17)},
          {"arguments", ["unsafe\n"]},
          {"directory", "../outside"},
          {"directory", String.duplicate("字", 81)},
          {"timeout_seconds", 301}
        ] do
      bad = Map.put(base, key, value)
      refute GuestChecks.declarations_valid?([bad])

      refute GuestChecks.current?(%{
               "checks" => [bad],
               "check_execution" => GuestChecks.policy_for([bad])
             })
    end
  end

  test "literal argument binding is length framed, order sensitive and covers all scope" do
    request = %{
      "request_id" => "a",
      "check_id" => "b",
      "input_key" => "c",
      "candidate_sha" => "d",
      "manifest_sha256" => "e",
      "image_spec_sha256" => "f",
      "toolchain" => "npm",
      "directory" => "sub/路径",
      "arguments" => ["test", "a b", "quote\"", "slash/"],
      "timeout_seconds" => 30
    }

    expected =
      :crypto.hash(:sha256, [
        Enum.map(
          ~w(request_id check_id input_key candidate_sha manifest_sha256 image_spec_sha256 toolchain directory),
          fn k ->
            v = request[k]
            <<byte_size(v)::32, v::binary>>
          end
        ),
        <<4::32>>,
        Enum.map(request["arguments"], fn v -> <<byte_size(v)::32, v::binary>> end),
        <<30::64>>
      ])
      |> Base.encode16(case: :lower)

    assert GuestChecks.check_digest(request) ==
             "11feff7b81335be7e814162c5812827bfdd56d341eda2de195ae92031ab66f55"

    assert GuestChecks.check_digest(request) == expected

    for field <- Map.keys(request) do
      changed =
        case field do
          "arguments" -> Enum.reverse(request[field])
          "timeout_seconds" -> 31
          _ -> request[field] <> "other"
        end

      refute GuestChecks.check_digest(Map.put(request, field, changed)) == expected
    end
  end

  defp wire do
    c = check("npm")
    id = Ecto.UUID.generate()

    check = %{
      "request_id" => id,
      "check_id" => c["id"],
      "input_key" => id,
      "candidate_sha" => String.duplicate("a", 40),
      "manifest_sha256" => String.duplicate("b", 64),
      "image_spec_sha256" => GuestChecks.image_spec(),
      "toolchain" => "npm",
      "directory" => ".",
      "arguments" => c["arguments"],
      "timeout_seconds" => c["timeout_seconds"]
    }

    request = %{"key" => Ecto.UUID.generate(), "check" => check}

    result =
      Map.take(check, ~w(request_id check_id input_key candidate_sha))
      |> Map.merge(%{
        "contract" => "isolated-guest-check-v1",
        "key" => request["key"],
        "status" => "passed",
        "check_sha256" => GuestChecks.check_digest(check),
        "intent_sha256" => String.duplicate("c", 64),
        "native_state" => 0,
        "vm_closed" => true,
        "cleanup_verified" => true,
        "source_unchanged" => true,
        "stdout_bytes" => 3,
        "observed_stdout_bytes" => 3,
        "stdout_sha256" => String.duplicate("d", 64),
        "exit_code" => 0
      })

    {request, result}
  end

  test "VM results require exact scope, literal binding, typed shutdown and bounded output" do
    {request, result} = wire()
    assert GuestChecks.normalize(Jason.encode!(result), request) == result

    for {field, value} <- [
          {"key", Ecto.UUID.generate()},
          {"check_sha256", String.duplicate("e", 64)},
          {"contract", "guest-check-v1"},
          {"native_state", true},
          {"vm_closed", false},
          {"cleanup_verified", "true"},
          {"source_unchanged", false},
          {"exit_code", 1},
          {"stdout_bytes", 65_537},
          {"elapsed_ms", 391_001},
          {"raw", "PRIVATE_CANARY"}
        ] do
      rejected = GuestChecks.normalize(Jason.encode!(Map.put(result, field, value)), request)
      assert rejected["cleanup_verified"] == false, field
      refute inspect(rejected) =~ "PRIVATE_CANARY"
    end

    for value <- ["{}", "[]", "null", "bad", String.duplicate("x", 8193)] do
      assert GuestChecks.normalize(value, request)["cleanup_verified"] == false
    end
  end

  test "preflight refusal is bound and distinct from missing VM shutdown" do
    {request, result} = wire()

    refused =
      result
      |> Map.take(
        ~w(contract key request_id check_id input_key candidate_sha check_sha256 cleanup_verified)
      )
      |> Map.merge(%{
        "status" => "image_changed",
        "native_started" => false,
        "admission_sha256" => String.duplicate("a", 64)
      })

    assert GuestChecks.normalize(Jason.encode!(refused), request) == refused

    refute GuestChecks.normalize(Jason.encode!(Map.delete(refused, "admission_sha256")), request)[
             "cleanup_verified"
           ]

    timeout =
      result
      |> Map.drop(~w(source_unchanged stdout_bytes observed_stdout_bytes stdout_sha256 exit_code))
      |> Map.put("status", "timeout")

    assert GuestChecks.normalize(Jason.encode!(timeout), request) == timeout
    refute Map.has_key?(timeout, "exit_code")

    finishing = Map.put(timeout, "elapsed_ms", 390_000)
    assert GuestChecks.normalize(Jason.encode!(finishing), request) == finishing
  end

  defp image do
    %{
      "status" => "check_image_prepared",
      "contract" => "isolated-check-image-v1",
      "key" => Ecto.UUID.generate(),
      "spec_sha256" => GuestChecks.image_spec(),
      "intent_sha256" => String.duplicate("a", 64),
      "cleanup_verified" => true,
      "kernel_sha256" => String.duplicate("b", 64),
      "kernel_bytes" => 100,
      "ramdisk_sha256" => String.duplicate("c", 64),
      "ramdisk_bytes" => 100,
      "manifest_sha256" => String.duplicate("d", 64),
      "toolchains" => %{
        "node" => "24.22.1",
        "npm" => "11.12.1",
        "elixir" => "1.20.3",
        "otp" => "28.5.0.8"
      }
    }
  end

  test "the owned worker binds a candidate VM run and rejects changed commands or lost closure" do
    {request, native_result} = wire()

    c = %{
      "id" => request["check"]["check_id"],
      "name" => "Tests",
      "executable" => "npm",
      "arguments" => ["test"],
      "directory" => ".",
      "timeout_seconds" => 30
    }

    attempt = %{
      id: request["check"]["request_id"],
      task_id: nil,
      deadline_at: DateTime.add(DateTime.utc_now(), 600),
      request: %{
        "snapshot" => %{"checks" => [c], "check_execution" => GuestChecks.policy_for([c])},
        "context" => %{"check_image" => image(), "head" => request["check"]["candidate_sha"]},
        "guest_check_runs" => %{c["id"] => request["key"]}
      }
    }

    preparation = %{
      "key" => attempt.id,
      "head" => request["check"]["candidate_sha"],
      "path" => "/synthetic",
      "device" => 1,
      "inode" => 1
    }

    for outcome <- ["passed", "failed", "missing_closure"] do
      native = fn ^attempt, operation, input, active? ->
        assert active?.()

        case operation do
          "prepare_check_input" ->
            assert input == %{
                     "key" => attempt.id,
                     "preparation" => Map.put(preparation, "status", "prepared")
                   }

            %{
              "status" => "check_input_prepared",
              "key" => attempt.id,
              "worktree_key" => attempt.id,
              "candidate_sha" => preparation["head"],
              "manifest_sha256" => request["check"]["manifest_sha256"],
              "elapsed_ms" => 42
            }

          "run_guest_check" ->
            assert input["check"] == request["check"]
            assert input["key"] == request["key"]
            refute Map.has_key?(input["input"]["input"], "elapsed_ms")

            assert input["deadline_unix_ms"] <=
                     DateTime.to_unix(attempt.deadline_at, :millisecond)

            case outcome do
              "passed" -> native_result
              "failed" -> Map.merge(native_result, %{"status" => "failed", "exit_code" => 1})
              "missing_closure" -> Map.delete(native_result, "vm_closed")
            end
        end
      end

      result = GuestChecks.run(attempt, preparation, fn -> true end, native)
      assert length(result["checks"]) == 1
      [row] = result["checks"]

      if outcome == "missing_closure" do
        refute result["cleanup_verified"]
        refute GuestChecks.valid_check?(attempt, row)
      else
        assert result["status"] == outcome
        assert result["cleanup_verified"]
        assert GuestChecks.valid_check?(attempt, row)

        changed =
          put_in(attempt.request["snapshot"]["checks"], [Map.put(c, "arguments", ["different"])])

        refute GuestChecks.valid_check?(changed, row)
        refute GuestChecks.valid_check?(attempt, Map.put(row, "key", Ecto.UUID.generate()))
        refute GuestChecks.valid_check?(attempt, Map.put(row, "image_key", Ecto.UUID.generate()))
      end
    end
  end
end
