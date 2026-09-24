# Opt-in installed RTK smoke: MIX_ENV=test mix run scripts/rtk_runtime_smoke.exs
alias Cuckoding.Plugins.RTK

assert = fn condition, label ->
  unless condition, do: raise("RTK smoke failed: #{label}")
end

System.put_env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
detection = RTK.discover()
assert.(detection.health == "available", "supported executable discovery")
root = Path.join(System.tmp_dir!(), "cuckoding-rtk-smoke-#{System.unique_integer([:positive])}")
File.mkdir_p!(Path.join(root, "agent"))
File.mkdir_p!(Path.join(root, "worktree"))

policy = %{
  "enabled" => true,
  "permissions" => %{"host_process" => true},
  "binary" => detection.binaries["rtk"]
}

request = %{
  run_dir: root,
  plugins: [%{"kind" => "shell_filter", "key" => "rtk", "policy" => policy}]
}

try do
  :ok = RTK.prepare(request)
  wrapper = RTK.wrapper(root)
  cwd = Path.join(root, "worktree")

  clean_env =
    Enum.map(System.get_env(), fn {key, _} -> {key, nil} end) ++
      [{"PATH", "/usr/bin:/bin:/usr/sbin:/sbin"}]

  command = fn args ->
    System.cmd(wrapper, args, cd: cwd, env: clean_env, stderr_to_stdout: true)
  end

  for {raw, rewritten} <- [
        {"git status", "rtk git status"},
        {"git status && git diff", "rtk git status && rtk git diff"},
        {"git commit -m 'quoted message'", "rtk git commit -m 'quoted message'"}
      ] do
    {output, status} = command.(["rewrite", raw])
    assert.(status == 3 and String.trim(output) == rewritten, "rewrite #{raw}")
  end

  for raw <- ["rtk git status", "rtk proxy git status"] do
    {output, status} = command.(["rewrite", raw])

    assert.(
      status == 3 and String.trim(output) == raw,
      "already wrapped remains unchanged, permission still required"
    )
  end

  assert.(command.(["rewrite", "definitely-unsupported-1044"]) == {"", 1}, "unsupported rewrite")

  canary = "rtk-secret-canary-1044"
  assert.(command.(["proxy", "/usr/bin/printf", canary]) == {canary, 0}, "exact output")
  {_output, status} = command.(["proxy", "/usr/bin/false"])
  assert.(status == 1, "nonzero exit")
  assert.(File.ls!(cwd) == [], "no :memory: or other worktree files")

  for file <- Path.wildcard(root <> "/**/*", match_dot: true), File.regular?(file) do
    assert.(not String.contains?(File.read!(file), canary), "no persisted canary")
  end

  File.mkdir_p!(Path.join(cwd, ".rtk"))
  File.write!(Path.join(cwd, ".rtk/filters.toml"), "invalid untrusted filter must not load")
  assert.(command.(["proxy", "/usr/bin/true"]) == {"", 0}, "repository filters ignored")

  IO.puts(
    "PASS RTK #{detection.binaries["rtk"]["version"]}: discovery, quoting, compounds, rewrite-only, raw output, exits, confined storage and canary checks"
  )
after
  File.rm_rf!(root)
end
