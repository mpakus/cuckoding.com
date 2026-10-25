defmodule Boss.FolderPickerTest do
  use ExUnit.Case, async: true
  alias Boss.FolderPicker

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "boss picker ü #{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "returns a real absolute folder without altering spaces or Unicode", %{root: root} do
    picker = picker("import sys; print(sys.argv[1])", [root])
    assert {:ok, ^root} = FolderPicker.choose(:repository, nil, picker)
  end

  test "cancellation is distinct from dialog failure" do
    for code <- ["print('')", "raise SystemExit(1)"] do
      assert :cancelled = FolderPicker.choose(:repository, nil, picker(code))
    end

    assert {:error, :failed} =
             FolderPicker.choose(:repository, nil, picker("raise SystemExit(9)"))
  end

  test "rejects missing, relative, multi-line and oversized results", %{root: root} do
    for value <- [
          "relative",
          "/no-such-boss-picker-directory",
          "/tmp\n/tmp",
          root <> "\n",
          String.duplicate("x", 20_000)
        ] do
      assert {:error, :failed} =
               FolderPicker.choose(
                 :repository,
                 nil,
                 picker("import sys; print(sys.argv[1])", [value])
               )
    end
  end

  test "reports unavailable native UI without launching a command" do
    picker =
      start_supervised!({FolderPicker, name: nil, command: fn _, _ -> {:error, :unavailable} end})

    assert {:error, :unavailable} = FolderPicker.choose(:repository, nil, picker)
  end

  test "permits one dialog at a time and timeout terminates the owned helper", %{root: root} do
    pidfile = Path.join(root, "pid")
    picker = picker(sleeper(), [pidfile], 400)
    request = Task.async(fn -> FolderPicker.choose(:repository, nil, picker) end)
    pid = wait_for_pid(pidfile)
    assert {:error, :busy} = FolderPicker.choose(:specs, root, picker)
    assert {:error, :timeout} = Task.await(request)
    assert_stopped(pid)
  end

  test "closing the requesting process terminates the dialog", %{root: root} do
    pidfile = Path.join(root, "pid")
    picker = picker(sleeper(), [pidfile])
    owner = spawn(fn -> FolderPicker.choose(:repository, nil, picker) end)
    pid = wait_for_pid(pidfile)
    Process.exit(owner, :kill)
    assert_stopped(pid)
    GenServer.stop(picker)
  end

  test "server shutdown terminates its native dialog", %{root: root} do
    pidfile = Path.join(root, "pid")
    picker = picker(sleeper(), [pidfile])
    owner = spawn(fn -> FolderPicker.choose(:repository, nil, picker) end)
    pid = wait_for_pid(pidfile)
    GenServer.stop(picker)
    assert_stopped(pid)
    Process.exit(owner, :kill)
  end

  defp picker(code, args \\ [], timeout \\ 5000) do
    spec =
      {FolderPicker,
       name: nil,
       timeout: timeout,
       command: fn _, _ -> {:ok, System.find_executable("python3"), ["-c", code | args], [1]} end}

    start_supervised!(Supervisor.child_spec(spec, id: make_ref()))
  end

  defp sleeper,
    do:
      "import os, pathlib, sys, time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); time.sleep(30)"

  defp wait_for_pid(path, attempts \\ 100)

  defp wait_for_pid(path, attempts) when attempts > 0 do
    case File.read(path) do
      {:ok, value} when value != "" ->
        String.to_integer(value)

      _ ->
        Process.sleep(10)
        wait_for_pid(path, attempts - 1)
    end
  end

  defp wait_for_pid(_, 0), do: flunk("Native helper did not start")

  defp assert_stopped(pid, attempts \\ 100)

  defp assert_stopped(pid, attempts) when attempts > 0 do
    case System.cmd("/bin/kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true) do
      {_, 0} ->
        Process.sleep(10)
        assert_stopped(pid, attempts - 1)

      _ ->
        :ok
    end
  end

  defp assert_stopped(_, 0), do: flunk("Native helper survived cleanup")
end
