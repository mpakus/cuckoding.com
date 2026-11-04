defmodule Boss.ResolutionAgentReportTest do
  use ExUnit.Case, async: false
  alias Boss.Deliveries.{ModelPolicy, Worker}
  @moduletag skip: :os.type() != {:unix, :darwin}

  setup do
    root = Path.join(System.tmp_dir!(), "boss-resolution-report-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    original = System.fetch_env!("PATH")
    executable = Path.join(root, "codex")

    File.write!(executable, """
    #!/usr/bin/env python3
    import json, pathlib, signal, sys
    signal.alarm(5)
    args = sys.argv[1:]
    assert args[args.index('--sandbox') + 1] == 'read-only'
    assert pathlib.Path(args[args.index('--output-schema') + 1]).name == 'resolution_schema.json'
    mode = json.loads(sys.stdin.read())['mode']
    pathlib.Path('called').write_text(mode)
    print(json.dumps({'type': 'turn.started'}), flush=True)
    print(json.dumps({'type': 'item.completed', 'item': {'type': 'agent_message', 'text': 'RAW_SECRET_SENTINEL'}}), flush=True)
    output = pathlib.Path(args[args.index('--output-last-message') + 1])
    if mode == 'auth':
        print(json.dumps({'type': 'error', 'code': 'invalid_api_key', 'message': 'RAW_SECRET_SENTINEL'}), flush=True)
        sys.exit(7)
    report = {'summary': 'Concise diagnosis', 'steps': ['Repair the boundary'], 'assumptions': [], 'external_action': None}
    if mode == 'oversized': report['steps'] = ['x' * 2000] * 20
    if mode == 'unicode': report['summary'] = 'é' * 1000 + 'x'
    text = json.dumps(report, ensure_ascii=False, separators=(',', ':'))
    if mode == 'invalid_json': text = '{RAW_SECRET_SENTINEL'
    if mode == 'replaced': output.unlink()
    output.write_text(text)
    pathlib.Path('report_bytes').write_text(str(len(text.encode('utf-8'))))
    print(json.dumps({'type': 'turn.completed', 'usage': {'input_tokens': 7, 'output_tokens': 3}}), flush=True)
    """)

    File.chmod!(executable, 0o700)
    System.put_env("PATH", root <> ":" <> original)
    on_exit(fn -> System.put_env("PATH", original) end)
    assert System.find_executable("codex") == executable
    %{root: root}
  end

  test "resolver records only fixed report diagnostics inside its existing summary", c do
    for {mode, code} <- [
          {"oversized", "report_too_large"},
          {"unicode", "invalid_summary"},
          {"invalid_json", "invalid_json"},
          {"replaced", "report_replaced"}
        ] do
      receipt = Worker.run_resolution(c.root, JSON.encode!(%{"mode" => mode}), profile())
      assert receipt["status"] == "failed" and receipt["outcome"] == "invalid_report"
      assert receipt["cleanup"] == "group_empty" and receipt["exit_code"] == 0
      assert receipt["eof"] == %{"stdout" => true, "stderr" => true}
      assert receipt["summary"]["validation_code"] == code

      bytes =
        if mode == "replaced",
          do: 0,
          else: c.root |> Path.join("report_bytes") |> File.read!() |> String.to_integer()

      assert receipt["summary"]["report_bytes"] == bytes
      assert receipt["summary"]["usage"]["input_tokens"] == 7
      refute Map.has_key?(receipt, "validation_code")
      refute Map.has_key?(receipt, "report_bytes")
      refute Map.has_key?(receipt, "report")
      refute inspect(receipt, limit: :infinity) =~ "RAW_SECRET_SENTINEL"
    end

    receipt = Worker.run_resolution(c.root, JSON.encode!(%{"mode" => "valid"}), profile())
    assert receipt["status"] == "finished"
    assert receipt["summary"]["validation_code"] == "valid"
    assert receipt["summary"]["report_bytes"] in 1..32_768
    assert receipt["report"]["steps"] == ["Repair the boundary"]
  end

  test "provider failure and Stop retain their cause instead of becoming report validation", c do
    receipt = Worker.run_resolution(c.root, JSON.encode!(%{"mode" => "auth"}), profile())
    assert receipt["status"] == "failed" and receipt["outcome"] == "exited"
    assert receipt["exit_code"] == 7 and receipt["summary"]["error_class"] == "auth"
    assert receipt["summary"]["validation_code"] == nil
    refute inspect(receipt, limit: :infinity) =~ "RAW_SECRET_SENTINEL"
    File.rm!(Path.join(c.root, "called"))
    send(self(), :stop)
    assert catch_throw(Worker.run_resolution(c.root, "{}", profile())) == {:halt, :cancelled}
    refute File.exists?(Path.join(c.root, "called"))
  end

  defp profile, do: ModelPolicy.route(1, :resolve, 1)
end
