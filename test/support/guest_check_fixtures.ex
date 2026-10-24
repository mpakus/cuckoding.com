defmodule Cuckoding.GuestCheckFixtures do
  @moduledoc false
  alias Cuckoding.GuestChecks

  def image(key) do
    %{
      "status" => "check_image_prepared",
      "contract" => "isolated-check-image-v1",
      "key" => key,
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

  def result(request, status \\ "passed") do
    row =
      Map.take(request["check"], ~w(request_id check_id input_key candidate_sha))
      |> Map.merge(%{
        "contract" => "isolated-guest-check-v1",
        "key" => request["key"],
        "status" => status,
        "check_sha256" => GuestChecks.check_digest(request["check"]),
        "intent_sha256" => String.duplicate("c", 64),
        "native_state" => 0,
        "vm_closed" => true,
        "cleanup_verified" => true,
        "source_unchanged" => true,
        "stdout_bytes" => 3,
        "observed_stdout_bytes" => 3,
        "stdout_sha256" => String.duplicate("d", 64),
        "exit_code" => if(status == "failed", do: 1, else: 0)
      })

    if request["feedback"] == Cuckoding.CheckFeedback.policy() and status == "failed" do
      text = "SYNTHETIC_ASSERTION: expected yes, got no."
      hash = :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)

      Map.merge(row, %{
        "stdout_bytes" => byte_size(text),
        "observed_stdout_bytes" => byte_size(text),
        "stdout_sha256" => hash,
        "failure_output" => %{
          "version" => Cuckoding.CheckFeedback.policy(),
          "excerpt" => text,
          "excerpt_sha256" => hash,
          "excerpt_bytes" => byte_size(text),
          "truncated" => false
        }
      })
    else
      row
    end
  end
end
