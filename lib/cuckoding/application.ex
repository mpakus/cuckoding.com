defmodule Cuckoding.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [Cuckoding.Repo, {Phoenix.PubSub, name: Cuckoding.PubSub}] ++
        runtime_children() ++
        shell_auth_child() ++ [CuckodingWeb.Endpoint]

    case Supervisor.start_link(children, strategy: :one_for_one, name: Cuckoding.Supervisor) do
      {:ok, _supervisor} = started ->
        :ok = Cuckoding.Shell.ready()
        started

      error ->
        error
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    CuckodingWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  def safe_mode?, do: Application.get_env(:cuckoding, :safe_mode, false)

  defp runtime_children do
    if safe_mode?() do
      []
    else
      [
        Cuckoding.Execution.StartupReconciler,
        {Cuckoding.Power.Manager, []},
        {Task.Supervisor, name: Cuckoding.GuidedRunSupervisor},
        {Registry, keys: :unique, name: Cuckoding.RunRegistry},
        Cuckoding.Execution.RunSupervisors,
        {DynamicSupervisor, strategy: :one_for_one, name: Cuckoding.Execution.ProcessWorkers},
        {Cuckoding.Plugins.Registry, Application.get_env(:cuckoding, :plugin_registry, [])},
        {Cuckoding.Plugins.Supervisor, []},
        {Cuckoding.Telemetry.ResourceSampler, []}
      ]
    end
  end

  defp shell_auth_child do
    case Application.get_env(:cuckoding, :shell_bootstrap_file) do
      path when is_binary(path) -> [{Cuckoding.Shell.Auth, path}]
      _other -> []
    end
  end
end
