defmodule Cuckoding.Shell do
  @moduledoc "Authenticated native-shell boundary and durable shutdown policy."

  import Ecto.Query

  alias Cuckoding.Execution.Run
  alias Cuckoding.Repo
  alias Cuckoding.Workflows.Approval

  @active_states ~w(queued running waiting paused)

  def status do
    %{
      active_runs:
        Repo.aggregate(from(run in Run, where: run.state in ^@active_states), :count, :id),
      attention:
        Repo.aggregate(
          from(approval in Approval, where: approval.decision == "pending"),
          :count,
          :id
        ),
      safe_mode: Cuckoding.Application.safe_mode?(),
      runtime_workers: is_pid(Process.whereis(Cuckoding.Execution.RunSupervisors))
    }
  end

  def shutdown(options \\ []) do
    policy = Keyword.get(options, :policy, configured_policy())
    prepare(policy)
  end

  def ready do
    if Cuckoding.Shell.Auth.enabled?() do
      port = CuckodingWeb.Endpoint.config(:http) |> Keyword.fetch!(:port)
      version = Application.spec(:cuckoding, :vsn) |> to_string()
      IO.puts(~s(READY {"port":#{port},"version":"#{version}"}))
    end

    :ok
  end

  defp configured_policy,
    do: Application.get_env(:cuckoding, :shell_quit_policy, Cuckoding.Shell.QuitPolicy)

  defp prepare(policy) when is_function(policy, 0), do: policy.()
  defp prepare(policy), do: policy.prepare()
end

defmodule Cuckoding.Shell.QuitPolicy do
  @moduledoc "Pauses admission and hibernates active runs before application shutdown."

  import Ecto.Query

  alias Cuckoding.Execution.BoardControl
  alias Cuckoding.Execution.Run
  alias Cuckoding.Repo
  alias Cuckoding.Shell.RunHibernator
  alias Cuckoding.Workflows.Task

  @active_states ~w(running waiting paused)

  def prepare do
    active_board_ids()
    |> Enum.reduce_while(:ok, fn board_id, :ok ->
      case BoardControl.control(board_id, :hibernate, run_controller: RunHibernator) do
        {:ok, _result} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:hibernate_failed, board_id, reason}}}
      end
    end)
  end

  defp active_board_ids do
    Repo.all(
      from(run in Run,
        join: task in Task,
        on: task.id == run.task_id,
        where: run.state in ^@active_states,
        distinct: true,
        order_by: task.board_id,
        select: task.board_id
      )
    )
  end
end

defmodule Cuckoding.Shell.RunHibernator do
  @moduledoc false

  import Ecto.Query

  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.Lifecycle
  alias Cuckoding.Execution.Run
  alias Cuckoding.Repo

  def hibernate(%Run{} = run) do
    case Repo.one(from(environment in Environment, where: environment.run_id == ^run.id)) do
      %Environment{} = environment ->
        options =
          Application.get_env(:cuckoding, :shell_hibernate_options, [])
          |> Keyword.put_new(:checkpoint, &checkpoint/1)

        with :ok <- port_allocation_available(environment, options) do
          Lifecycle.hibernate(run, environment, "shell:hibernate:#{run.id}", options)
        end

      nil ->
        {:error, :environment_not_found}
    end
  end

  defp checkpoint(attempt) do
    checkpoint =
      (attempt.checkpoint_json || %{})
      |> Map.put_new("stage_attempt_id", attempt.id)
      |> Map.put("reason", "shell_quit")

    {:ok, checkpoint}
  end

  defp port_allocation_available(%Environment{port: nil}, _options), do: :ok

  defp port_allocation_available(%Environment{} = environment, options) do
    case options[:allocation] do
      %Cuckoding.Execution.PortAllocator.Allocation{environment: allocated}
      when allocated.id == environment.id and allocated.port == environment.port ->
        :ok

      _other ->
        {:error, :port_allocation_required}
    end
  end
end

defmodule Cuckoding.Shell.Auth do
  @moduledoc "Single-use bootstrap and browser-session token issuer."

  use GenServer

  import Bitwise

  @browser_token_ttl_seconds 60
  @maximum_file_bytes 1_024

  def start_link(path), do: GenServer.start_link(__MODULE__, path, name: __MODULE__)

  def enabled?, do: is_pid(Process.whereis(__MODULE__))

  def required?,
    do: enabled?() or is_binary(Application.get_env(:cuckoding, :shell_bootstrap_file))

  def bootstrap(token), do: call({:bootstrap, token}, :error)
  def browser_token(shell_token), do: call({:browser_token, shell_token}, :error)
  def consume_browser_token(token), do: call({:consume, token}, false)
  def shell?(token), do: call({:shell?, token}, false)

  @impl true
  def init(path) do
    with {:ok, bootstrap} <- read_bootstrap(path),
         :ok <- File.rm(path) do
      {:ok, %{bootstrap: bootstrap, shell: nil, browser: %{}}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:bootstrap, token}, _from, %{bootstrap: bootstrap} = state) do
    if secure_equal?(token, bootstrap) do
      shell = token()
      {:reply, {:ok, shell}, %{state | bootstrap: nil, shell: shell}}
    else
      {:reply, :error, state}
    end
  end

  def handle_call({:browser_token, shell}, _from, state) do
    if secure_equal?(shell, state.shell) do
      token = token()
      expires_at = System.monotonic_time(:second) + @browser_token_ttl_seconds
      {:reply, {:ok, token}, put_in(state.browser[token], expires_at)}
    else
      {:reply, :error, state}
    end
  end

  def handle_call({:consume, token}, _from, state) do
    {expires_at, browser} = Map.pop(state.browser, token)
    valid? = is_integer(expires_at) and expires_at >= System.monotonic_time(:second)
    {:reply, valid?, %{state | browser: browser}}
  end

  def handle_call({:shell?, token}, _from, state),
    do: {:reply, secure_equal?(token, state.shell), state}

  defp read_bootstrap(path) when is_binary(path) do
    with {:ok, %{type: :regular, mode: mode, size: size}} when size <= @maximum_file_bytes <-
           File.lstat(path),
         true <- (mode &&& 0o077) == 0,
         {:ok, contents} <- File.read(path),
         [secret, bootstrap] <- String.split(String.trim(contents), "\n", parts: 2),
         true <- byte_size(secret) >= 64 and byte_size(bootstrap) >= 43 do
      {:ok, bootstrap}
    else
      _other -> {:error, :invalid_bootstrap_file}
    end
  end

  defp read_bootstrap(_path), do: {:error, :invalid_bootstrap_file}

  defp token, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

  defp call(message, fallback) do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) -> GenServer.call(pid, message)
      nil -> fallback
    end
  catch
    :exit, _reason -> fallback
  end

  defp secure_equal?(left, right) when is_binary(left) and is_binary(right),
    do: byte_size(left) == byte_size(right) and Plug.Crypto.secure_compare(left, right)

  defp secure_equal?(_left, _right), do: false
end
