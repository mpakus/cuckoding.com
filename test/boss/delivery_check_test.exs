defmodule Boss.DeliveryCheckTest do
  use ExUnit.Case, async: false
  alias Boss.Deliveries.Worker
  @moduletag skip: :os.type() != {:unix, :darwin}

  setup do
    root = Path.join(System.tmp_dir!(), "boss-delivery-check-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      config: %{
        "argv" => ["/usr/bin/printf", "complete output"],
        "timeout_ms" => 1000,
        "output_limit" => 1024
      }
    }
  end

  test "complete output is returned transiently while receipt keeps only its digest", ctx do
    {receipt, output} = Worker.run_check(ctx.root, ctx.config, fn -> :ok end)
    assert receipt["status"] == "finished" and receipt["cleanup"] == "group_empty"
    assert receipt["exit_code"] == 0 and receipt["output_complete"]
    assert receipt["eof"] == %{"stdout" => true, "stderr" => true}
    assert output == %{"stdout" => "complete output", "stderr" => ""}
    assert byte_size(receipt["output_hash"]) == 64
    refute inspect(receipt) =~ "complete output"
  end

  test "nonzero exit is actionable only with complete output and unchanged candidate", ctx do
    config = %{ctx.config | "argv" => ["/bin/sh", "-c", "printf failure; exit 3"]}
    {receipt, output} = Worker.run_check(ctx.root, config, fn -> :ok end)
    assert receipt["status"] == "failed" and receipt["outcome"] == "checks_failed"
    assert output["stdout"] == "failure" and receipt["output_complete"]
    Process.put(:check_verifications, 0)

    {receipt, _} =
      Worker.run_check(ctx.root, config, fn ->
        count = Process.get(:check_verifications)
        Process.put(:check_verifications, count + 1)
        if count == 0, do: :ok, else: {:error, :candidate_changed}
      end)

    assert receipt["outcome"] == "candidate_changed"
  end

  test "invalid UTF8 and output overflow never return partial evidence", ctx do
    for script <- ["printf '\\377'", "printf '12345'"] do
      config = %{ctx.config | "argv" => ["/bin/sh", "-c", script], "output_limit" => 4}
      {receipt, output} = Worker.run_check(ctx.root, config, fn -> :ok end)
      assert receipt["status"] == "failed"
      refute receipt["output_complete"]
      assert output == %{}
    end
  end

  test "Stop before execution starts no check process", ctx do
    send(self(), :stop)

    {receipt, output} =
      Worker.run_check(ctx.root, ctx.config, fn -> flunk("must not verify after Stop") end)

    assert receipt["status"] == "cancelled"
    assert output == %{}
  end
end
