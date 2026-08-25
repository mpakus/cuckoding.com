defmodule AgentDesk.Providers.SessionWorkerTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Providers
  alias AgentDesk.Providers.SessionWorker

  @max_fs_bytes 1_000_000

  test "stopped-worker control calls normalize to not_started" do
    id = Ecto.UUID.generate()

    assert {:error, :not_started} = SessionWorker.fetch(id)
    assert {:error, :not_started} = SessionWorker.prompt(id, "hello")
    assert {:error, :not_started} = SessionWorker.interrupt(id)
    assert {:error, :not_started} = SessionWorker.approve(id, "request", "deny")
    assert {:error, :not_started} = SessionWorker.terminate_session(id)
    assert {:error, :not_started} = Providers.stop_worker(id)
  end

  test "ACP fs/read_text_file returns regular UTF-8 files" do
    root = tmp_dir!("acp-read")
    File.mkdir_p!(root)
    File.write!(Path.join(root, "notes.txt"), "one\ntwo\nthree")

    assert {:jsonrpc_result, "7", %{"content" => "two\nthree"}} =
             SessionWorker.fs_read_action(root, "7", %{
               "path" => "notes.txt",
               "line" => 2
             })
  end

  test "ACP fs/read_text_file rejects an oversized file" do
    root = tmp_dir!("acp-oversized")
    File.mkdir_p!(root)
    File.write!(Path.join(root, "large.txt"), :binary.copy("x", @max_fs_bytes + 1))

    assert {:jsonrpc_error, "8", -32_000, "File is too large to read"} =
             SessionWorker.fs_read_action(root, "8", %{"path" => "large.txt"})
  end

  test "ACP fs/read_text_file rejects symlinks and directories" do
    root = tmp_dir!("acp-special")
    File.mkdir_p!(root)
    File.write!(Path.join(root, "target.txt"), "secret")
    File.ln_s!("target.txt", Path.join(root, "linked.txt"))

    assert {:jsonrpc_error, "9", -32_000, "Path is not a regular file"} =
             SessionWorker.fs_read_action(root, "9", %{"path" => "linked.txt"})

    assert {:jsonrpc_error, "10", -32_000, "Path is not a regular file"} =
             SessionWorker.fs_read_action(root, "10", %{"path" => root})
  end

  test "ACP fs/read_text_file rejects a FIFO when mkfifo is available" do
    root = tmp_dir!("acp-fifo")
    File.mkdir_p!(root)
    fifo = Path.join(root, "pipe")

    case System.find_executable("mkfifo") do
      nil ->
        :ok

      executable ->
        {_output, 0} = System.cmd(executable, [fifo], stderr_to_stdout: true)

        assert {:jsonrpc_error, "11", -32_000, "Path is not a regular file"} =
                 SessionWorker.fs_read_action(root, "11", %{"path" => fifo})
    end
  end

  defp tmp_dir!(name) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "agentdesk-#{name}-#{System.unique_integer([:positive, :monotonic])}"
      )

    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end
end
