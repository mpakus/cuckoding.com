defmodule Cuckoding.Execution.PortAllocator do
  @moduledoc "Allocates project-scoped loopback ports with durable exclusive leases."

  import Ecto.Query

  alias Cuckoding.Execution
  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.Leases
  alias Cuckoding.Projects.Project
  alias Cuckoding.Repo

  @default_ttl_ms 30_000

  defmodule Allocation do
    @moduledoc false
    defstruct [:environment, :lease, :token]
  end

  defimpl Inspect, for: Allocation do
    import Inspect.Algebra

    def inspect(allocation, options) do
      concat([
        "#Cuckoding.Execution.PortAllocator.Allocation<",
        to_doc(
          %{environment: allocation.environment.id, port: allocation.environment.port},
          options
        ),
        ">"
      ])
    end
  end

  @doc "Allocates the first OS-available, unleased port in the project's range."
  def allocate(%Project{} = project, %Environment{} = environment, options \\ []) do
    ttl_ms = Keyword.get(options, :ttl_ms, @default_ttl_ms)

    with true <- project_owns?(project.id, environment.id),
         true <- is_nil(environment.port),
         true <- is_integer(ttl_ms) and ttl_ms > 0 do
      allocate_in_range(project, environment, ttl_ms, options)
    else
      false when not is_nil(environment.port) -> {:error, :port_already_allocated}
      false -> {:error, :environment_project_mismatch}
      _other -> {:error, :invalid_port_lease_ttl}
    end
  end

  @doc "Renews the durable port lease without persisting its bearer token."
  def heartbeat(%Allocation{} = allocation, ttl_ms \\ @default_ttl_ms) do
    with {:ok, lease} <- Leases.heartbeat(allocation.lease.id, allocation.token, ttl_ms) do
      {:ok, %{allocation | lease: lease}}
    end
  end

  @doc "Releases a port and clears its preview URL for hibernate or stop."
  def release(%Allocation{} = allocation, state \\ "hibernated")
      when state in ["hibernated", "stopped", "failed"] do
    with {:ok, _lease} <- Leases.release(allocation.lease.id, allocation.token) do
      Execution.update_environment_preview(allocation.environment, %{
        port: nil,
        preview_url: nil,
        ports_json: %{},
        state: state
      })
    end
  end

  @doc "Reports whether one loopback TCP port can currently be bound."
  def available?(port) when is_integer(port) and port in 1_024..65_535 do
    case :gen_tcp.listen(port, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true]) do
      {:ok, socket} ->
        :ok = :gen_tcp.close(socket)
        true

      {:error, _reason} ->
        false
    end
  end

  def available?(_port), do: false

  defp allocate_in_range(project, environment, ttl_ms, options) do
    Enum.reduce_while(
      project.port_range_start..project.port_range_end,
      {:error, :no_ports_available},
      &claim_candidate(&1, &2, environment, ttl_ms, options)
    )
  end

  defp claim_candidate(port, _result, environment, ttl_ms, options) do
    case claim(port, environment, ttl_ms, options) do
      {:ok, allocation} ->
        {:halt, {:ok, allocation}}

      {:error, reason} when reason in [:already_leased, :port_in_use] ->
        {:cont, {:error, :no_ports_available}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp claim(port, environment, ttl_ms, options) do
    resource_id = "tcp:127.0.0.1:#{port}"

    if available?(port) do
      case Leases.acquire("port", resource_id, environment.run_id, ttl_ms, options) do
        {:ok, lease, token} -> persist_claim(environment, port, lease, token, options)
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :port_in_use}
    end
  end

  defp persist_claim(environment, port, lease, token, options) do
    result =
      if available?(port),
        do: persist(environment, port, lease.id),
        else: {:error, :port_in_use}

    case result do
      {:ok, updated} ->
        {:ok, %Allocation{environment: updated, lease: lease, token: token}}

      {:error, reason} ->
        {:ok, _released} = Leases.release(lease.id, token, options)
        {:error, reason}
    end
  end

  defp persist(environment, port, lease_id) do
    Execution.update_environment_preview(environment, %{
      port: port,
      preview_url: "http://127.0.0.1:#{port}",
      ports_json: %{"preview" => port, "lease_id" => lease_id},
      state: "prepared"
    })
  end

  defp project_owns?(project_id, environment_id) do
    Repo.exists?(
      from(environment in Environment,
        join: run in Cuckoding.Execution.Run,
        on: run.id == environment.run_id,
        join: task in Cuckoding.Workflows.Task,
        on: task.id == run.task_id,
        join: board in Cuckoding.Workflows.Board,
        on: board.id == task.board_id,
        where: environment.id == ^environment_id and board.project_id == ^project_id
      )
    )
  end
end

defmodule Cuckoding.Execution.Preview do
  @moduledoc "Starts, probes, and stops one declared loopback preview server."

  alias Cuckoding.Execution.CommandPolicy
  alias Cuckoding.Execution.LocalProcessRunner
  alias Cuckoding.Execution.PortAllocator
  alias Cuckoding.Execution.Run
  alias Cuckoding.Projects.ProjectConfigVersion
  alias Cuckoding.Repo

  @connect_timeout 500
  @request_timeout 1_000

  defmodule Service do
    @moduledoc false
    defstruct [:allocation, :handle, :runner, :health_path]
  end

  @doc "Starts the trusted `dev_server` declaration with fixed loopback port variables."
  def start(%Run{} = run, %PortAllocator.Allocation{} = allocation, options \\ []) do
    runner = Keyword.get(options, :runner, LocalProcessRunner)
    health_path = Keyword.get_lazy(options, :health_path, fn -> configured_health_path(run) end)
    port = allocation.environment.port

    result =
      with true <- is_integer(port),
           :ok <- valid_health_path(health_path),
           env = preview_environment(options, port),
           runner_options = runner_options(options, runner, env),
           {:ok, handle} <-
             CommandPolicy.start(run, allocation.environment, "dev_server", runner_options) do
        {:ok,
         %Service{
           allocation: allocation,
           handle: handle,
           runner: runner,
           health_path: health_path
         }}
      else
        false -> {:error, :port_not_allocated}
        {:error, reason} -> {:error, reason}
      end

    case result do
      {:ok, _service} -> result
      {:error, reason} -> release_failed_start(allocation, reason)
    end
  end

  @doc "Stops the preview process before releasing its port lease."
  def stop(%Service{} = service, state \\ "stopped") do
    with {:ok, _result} <- stop_runner(service),
         do: PortAllocator.release(service.allocation, state)
  end

  @doc "Measures one HTTP health response without redirects or non-loopback access."
  def health(%Service{} = service, options \\ []) do
    probe(
      service.allocation.environment.preview_url,
      service.health_path,
      options
    )
  end

  def probe(url, path \\ "/", options \\ [])

  def probe(url, path, options) when is_binary(url) and is_binary(path) do
    with :ok <- valid_health_path(path),
         {:ok, port} <- loopback_port(url),
         {:ok, socket} <-
           :gen_tcp.connect(
             {127, 0, 0, 1},
             port,
             [:binary, active: false],
             Keyword.get(options, :connect_timeout, @connect_timeout)
           ) do
      request(socket, port, path, Keyword.get(options, :request_timeout, @request_timeout))
    else
      {:error, :econnrefused} -> {:ok, :unavailable}
      {:error, :timeout} -> {:ok, :unavailable}
      {:error, reason} -> {:error, reason}
    end
  end

  def probe(_url, _path, _options), do: {:error, :invalid_preview_url}

  defp request(socket, port, path, timeout) do
    request = "GET #{path} HTTP/1.1\r\nHost: 127.0.0.1:#{port}\r\nConnection: close\r\n\r\n"

    try do
      with :ok <- :gen_tcp.send(socket, request),
           {:ok, response} <- :gen_tcp.recv(socket, 0, timeout),
           {:ok, status} <- status(response) do
        if status in 200..299,
          do: {:ok, :healthy},
          else: {:ok, {:unhealthy, status}}
      end
    after
      :gen_tcp.close(socket)
    end
  end

  defp status(response) do
    case Regex.run(~r/^HTTP\/1\.[01] (\d{3}) /, response, capture: :all_but_first) do
      [status] -> {:ok, String.to_integer(status)}
      _other -> {:error, :invalid_http_response}
    end
  end

  defp loopback_port(url) do
    case URI.parse(url) do
      %URI{scheme: "http", host: "127.0.0.1", port: port, userinfo: nil}
      when is_integer(port) and port in 1_024..65_535 ->
        {:ok, port}

      _other ->
        {:error, :non_loopback_preview_url}
    end
  end

  defp valid_health_path(path) do
    if String.starts_with?(path, "/") and not String.contains?(path, ["\r", "\n"]),
      do: :ok,
      else: {:error, :invalid_health_path}
  end

  defp stop_runner(%Service{runner: runner, handle: handle, allocation: allocation}) do
    if function_exported?(runner, :stop, 1),
      do: runner.stop(handle),
      else: runner.destroy(allocation.environment, [])
  end

  defp preview_environment(options, port) do
    options
    |> Keyword.get(:env, %{})
    |> Map.merge(%{
      "PORT" => Integer.to_string(port),
      "CUCKODING_PORT" => Integer.to_string(port),
      "HOST" => "127.0.0.1"
    })
  end

  defp runner_options(options, runner, environment) do
    options
    |> Keyword.put(:runner, runner)
    |> Keyword.put(:env, environment)
    |> Keyword.update(:environment_allowlist, ["HOST"], &["HOST" | &1])
  end

  defp release_failed_start(allocation, reason) do
    case PortAllocator.release(allocation, "failed") do
      {:ok, _environment} -> {:error, reason}
      {:error, release_reason} -> {:error, {:preview_start_failed, reason, release_reason}}
    end
  end

  defp configured_health_path(run) do
    case Repo.get(ProjectConfigVersion, run.policy_snapshot_id) do
      %ProjectConfigVersion{config_json: config} ->
        get_in(config, ["ports", "health_path"]) || "/"

      nil ->
        "/"
    end
  end
end

defmodule Cuckoding.Execution.WorktreeOpener do
  @moduledoc "Opens one recorded worktree in Finder or the configured editor after user action."

  alias Cuckoding.Execution.Environment
  alias Cuckoding.Repo

  @open "/usr/bin/open"
  @application ~r/^[a-zA-Z0-9 ._+-]+$/

  def open(environment, destination, options \\ [])

  def open(%Environment{} = environment, destination, options)
      when destination in [:finder, :editor] do
    launcher = Keyword.get(options, :launcher, &System.cmd/2)
    editor = Keyword.get(options, :editor_application, "Cursor")

    with %Environment{} = persisted <- Repo.get(Environment, environment.id),
         true <- persisted.worktree_path == environment.worktree_path,
         {:ok, path} <- canonical_directory(environment.worktree_path),
         {:ok, args} <- arguments(destination, editor, path),
         {_output, 0} <- launcher.(@open, args) do
      :ok
    else
      nil -> {:error, :environment_not_found}
      false -> {:error, :worktree_path_mismatch}
      {:error, reason} -> {:error, reason}
      {_output, _status} -> {:error, :open_failed}
    end
  end

  def open(%Environment{}, _destination, _options), do: {:error, :invalid_destination}

  defp arguments(:finder, _editor, path), do: {:ok, [path]}

  defp arguments(:editor, editor, path) do
    if is_binary(editor) and Regex.match?(@application, editor),
      do: {:ok, ["-a", editor, path]},
      else: {:error, :invalid_editor_application}
  end

  defp canonical_directory(path) do
    case File.stat(path) do
      {:ok, %{type: :directory}} ->
        case System.cmd("/bin/pwd", ["-P"], cd: path, stderr_to_stdout: true) do
          {resolved, 0} -> {:ok, String.trim(resolved)}
          {_output, _status} -> {:error, :path_resolution_failed}
        end

      _other ->
        {:error, :missing_worktree}
    end
  end
end
