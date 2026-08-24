defmodule AgentDesk.Providers.LiveCliSuite do
  @moduledoc false

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      use AgentDesk.DataCase

      alias AgentDesk.A2A.AgentCard
      alias AgentDesk.Agents
      alias AgentDesk.GitRepo
      alias AgentDesk.Isolation
      alias AgentDesk.Projects
      alias AgentDesk.Providers
      alias AgentDesk.Providers.Discovery
      alias AgentDesk.Providers.SessionWorker
      alias AgentDesk.Repo
      alias AgentDesk.Scope

      @moduletag :live_cli
      @moduletag timeout: 45_000

      @provider_key Keyword.fetch!(opts, :key)
      @binary Keyword.fetch!(opts, :binary)

      if match?({:error, :not_found}, Discovery.find_executable(@binary)) do
        @moduletag skip: "#{@binary} CLI is not installed"
      end

      setup do
        {:ok, exe} = Discovery.find_executable(@binary)
        repo = GitRepo.tmp_repo!()
        {:ok, project} = Projects.open_project(repo)

        %{executable: exe, project: project, scope: Scope.for_project(project)}
      end

      test "#{@provider_key} probe reports the installed CLI version", %{executable: exe} do
        assert {:ok, result} =
                 Discovery.probe(@provider_key, fixture: false, executable: exe)

        assert result.executable == exe
        assert is_binary(result.version)
        refute result.version in ["", "fixture"]
      end

      test "#{@provider_key} handshake registers a session without a paid prompt", %{
        scope: scope,
        executable: exe
      } do
        assert {:ok, session} =
                 Providers.start_session(
                   scope,
                   %{provider: @provider_key, display_name: "live-#{@provider_key}"},
                   fixture: false,
                   executable: exe
                 )

        settled =
          wait_until(
            fn ->
              updated = Repo.get!(Agents.Session, session.id)

              cond do
                updated.provider_session_id &&
                    updated.status in ["idle", "completed", "working"] ->
                  {:ready, updated}

                updated.status == "failed" ->
                  {:timed_out, updated}

                true ->
                  false
              end
            end,
            500
          )

        assert settled, "#{@provider_key} did not settle"
        assert {:ok, _pid} = SessionWorker.fetch(session.id)
        assert File.exists?(Path.join(Isolation.dir(session), "env"))

        case settled do
          {:ready, _ready} ->
            assert Repo.get_by(AgentCard, agent_session_id: session.id)
            assert :ok = SessionWorker.interrupt(session.id)
            assert :ok = SessionWorker.terminate_session(session.id)

          {:timed_out, timed_out} ->
            refute timed_out.provider_session_id
            assert :ok = SessionWorker.terminate_session(session.id)
        end
      end
    end
  end
end
