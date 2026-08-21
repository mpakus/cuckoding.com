defmodule AgentDesk.Providers.LifecycleSuite do
  @moduledoc false

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      use AgentDesk.DataCase

      alias AgentDesk.A2A.AgentCard
      alias AgentDesk.Agents
      alias AgentDesk.GitRepo
      alias AgentDesk.Projects
      alias AgentDesk.Providers
      alias AgentDesk.Providers.SessionWorker
      alias AgentDesk.Repo
      alias AgentDesk.Scope

      @provider_key Keyword.fetch!(opts, :key)

      setup do
        repo = GitRepo.tmp_repo!()
        {:ok, project} = Projects.open_project(repo)
        %{project: project, scope: Scope.for_project(project), repo: repo}
      end

      test "handshake registers an Agent Card and persists the provider session id", %{
        scope: scope
      } do
        {:ok, session} =
          Providers.start_session(scope, %{provider: @provider_key, display_name: @provider_key})

        ready =
          wait_until(fn ->
            updated = Repo.get!(Agents.Session, session.id)
            updated.provider_session_id && updated
          end)

        assert ready
        assert ready.status in ["idle", "completed", "working"]
        assert Repo.get_by(AgentCard, agent_session_id: session.id)
        assert SessionWorker.fetch(session.id) != {:error, :not_started}
      end

      test "prompt completes a turn without blocking other work", %{scope: scope} do
        {:ok, session} =
          Providers.start_session(scope, %{provider: @provider_key, display_name: @provider_key})

        wait_until(fn -> Repo.get!(Agents.Session, session.id).provider_session_id end)
        assert :ok = SessionWorker.prompt(session.id, "hello")

        assert wait_until(fn ->
                 Repo.get!(Agents.Session, session.id).status in ["idle", "completed", "working"]
               end)
      end

      test "unexpected crash is a recoverable failed state", %{scope: scope} do
        {:ok, session} =
          Providers.start_session(
            scope,
            %{provider: @provider_key, display_name: @provider_key},
            peer_args: ["--crash"]
          )

        failed =
          wait_until(fn ->
            status = Repo.get!(Agents.Session, session.id).status
            status == "failed" && status
          end)

        assert failed == "failed"
      end
    end
  end
end
