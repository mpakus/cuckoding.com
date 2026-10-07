defmodule Cuckoding.AuthorizationTest do
  use Cuckoding.DataCase
  alias Cuckoding.{Codex, Command, Event, Foundation}

  @url "https://auth.openai.com/oauth/authorize?state=fixture-link-canary"

  setup do
    root = Path.join("/private/tmp", "cuckoding-auth-" <> Ecto.UUID.generate())
    File.mkdir!(root)
    path = Path.join(root, "codex")
    File.write!(path, "#!/bin/sh\nexit 1\n")
    File.chmod!(path, 0o700)
    previous = Application.get_env(:cuckoding, :native_helper)
    Codex.init_login_links()

    on_exit(fn ->
      Application.put_env(:cuckoding, :native_helper, previous)
      File.rm_rf!(root)
    end)

    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), 0, path, true)
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "supported", "version" => "0.146.0"})
    %{root: root, path: path}
  end

  defp enqueue(operation \\ :login) do
    Foundation.authorize_codex(
      Ecto.UUID.generate(),
      Foundation.workspace().revision,
      operation,
      true
    )
  end

  test "fresh consent is durable and exclusive; account mutation clears old cache" do
    Foundation.workspace()
    |> Ecto.Changeset.change(
      connection: %{"authorization" => "chatgpt", "models" => [%{"id" => "old"}]}
    )
    |> Repo.update!()

    assert {:error, :confirmation_required} =
             Foundation.authorize_codex(Ecto.UUID.generate(), 1, :login, false)

    key = Ecto.UUID.generate()
    assert {:ok, command} = Foundation.authorize_codex(key, 1, :login, true)
    assert {:ok, ^command} = Foundation.authorize_codex(key, 1, :login, true)
    assert Foundation.workspace().connection["models"] == []
    assert Foundation.workspace().connection["authorization"] == "unknown"
    assert {:ok, %{state: "rejected", result: "profile_busy"}} = enqueue(:logout)

    assert {:ok, %{state: "rejected", result: "profile_busy"}} =
             Foundation.discover(Ecto.UUID.generate(), 1)

    assert {:ok, claim} = Foundation.claim()
    assert :ok = Foundation.login_waiting(claim)
    assert :ok = Foundation.login_waiting(claim)

    assert Repo.aggregate(from(e in Event, where: e.kind == "login.awaiting_browser"), :count) ==
             1
  end

  test "cancel remains pending until cleanup and late success cannot restore models" do
    {:ok, command} = enqueue()
    {:ok, claim} = Foundation.claim()
    Foundation.login_waiting(claim)
    Codex.put_login_link(command.id, @url)
    assert Foundation.login_link(Foundation.last_probe("login_codex")) == @url
    Foundation.cancel_probe(command.id)
    Foundation.cancel_probe(command.id)
    assert Foundation.pending?()
    assert Foundation.last_probe("login_codex").state == "cancelling"
    refute Foundation.login_link(Foundation.last_probe("login_codex"))

    assert {:ok, %{state: "cancelled", result: "recheck_required"}} =
             Foundation.finish(claim, %{
               "status" => "checked",
               "authorization" => "chatgpt",
               "catalog_status" => "fresh",
               "models" => []
             })

    refute Foundation.pending?()
    assert Foundation.workspace().connection["status"] == "cancelled"
    refute Foundation.workspace().connection["authorization"] == "chatgpt"
    refute inspect(Repo.all(Command)) =~ "fixture-link-canary"
    refute inspect(Repo.all(Event)) =~ "fixture-link-canary"
    refute inspect(Foundation.workspace()) =~ "fixture-link-canary"

    {:ok, command} = enqueue(:logout)
    {:ok, claim} = Foundation.claim()
    Foundation.cancel_probe(command.id)
    Foundation.finish(claim, %{"status" => "cleanup_uncertain"})
    assert Foundation.workspace().connection["status"] == "cleanup_uncertain"
  end

  test "interrupted and sleep-expired logins are uncertain and never replayed" do
    {:ok, _} = enqueue()
    {:ok, claim} = Foundation.claim(1_000)
    assert {:ok, nil} = Foundation.claim(630_999)

    assert {:ok, %{state: "failed", result: "interrupted", attempts: 1}} =
             Foundation.claim(631_001)

    assert {:ok, nil} = Foundation.claim(631_002)
    assert {:error, :lost_claim} = Foundation.finish(claim, %{"status" => "checked"})
    assert Foundation.workspace().connection["authorization"] == "unknown"
    assert Foundation.workspace().connection["models"] == []
    assert :error = Foundation.login_waiting(claim)
  end

  test "only bounded official login links are transient and expire" do
    id = Ecto.UUID.generate()

    for url <- [
          "http://auth.openai.com/oauth/authorize",
          "https://auth.openai.com.evil.test/oauth/authorize",
          "https://user@auth.openai.com/oauth/authorize",
          "https://auth.openai.com:444/oauth/authorize",
          "https://auth.openai.com/oauth/authorize#secret",
          "https://chatgpt.com/logout",
          @url <> "\n",
          String.duplicate("a", 8193)
        ] do
      refute Codex.valid_login_url?(url)
      Codex.put_login_link(id, url)
      refute Codex.login_link(id)
    end

    Codex.put_login_link(id, @url)
    assert Codex.login_link(id) == @url
    :ets.insert(:cuckoding_login_link, {id, @url, System.system_time(:second) - 1})
    refute Codex.login_link(id)
    Codex.clear_login_link()
    refute Codex.login_link(id)
  end

  defp helper(root, body) do
    helper = Path.join(root, "helper")
    File.write!(helper, "#!/bin/sh\n" <> body)
    File.chmod!(helper, 0o700)
    Application.put_env(:cuckoding, :native_helper, helper)
  end

  test "split transient frames stay out of results and cancellation waits for helper exit", %{
    root: root,
    path: path
  } do
    helper(root, """
    printf '%s' '{"status":"awaiting_'
    sleep 0.02
    printf '%s\\n' 'login","auth_url":"#{@url}","raw":"fixture-secret"}'
    read -r cancellation
    echo cleaned > "$3/cleaned"
    printf '%s\\n' '{"status":"cancelled","raw":"fixture-secret"}'
    """)

    {:ok, identity} = Codex.executable(path)
    Process.put(:auth_active, true)

    result =
      Codex.authorize(identity, root, :login, fn -> Process.get(:auth_active) end, fn url ->
        assert url == @url
        Process.put(:auth_active, false)
      end)

    assert result == %{"status" => "cancelled"}
    assert File.exists?(Path.join(root, "cleaned"))
    refute inspect(result) =~ "fixture-"
  end

  test "unsafe or repeated login instructions fail without forwarding raw output", %{
    root: root,
    path: path
  } do
    {:ok, identity} = Codex.executable(path)

    for frames <- [
          ~s({"status":"awaiting_login","auth_url":"https://evil.test/fixture-secret"}),
          ~s({"status":"awaiting_login","auth_url":"#{@url}"}\n{"status":"awaiting_login","auth_url":"#{@url}"}),
          String.duplicate("x", 524_289)
        ] do
      helper(root, "printf '%s\\n' '#{frames}'\n")
      result = Codex.authorize(identity, root, :login, fn -> true end, fn _ -> :ok end)
      assert result == %{"status" => "invalid_output"}
      refute inspect(result) =~ "fixture-"
    end
  end
end
