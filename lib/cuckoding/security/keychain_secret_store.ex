defmodule Cuckoding.Security.KeychainSecretStore do
  @moduledoc "macOS Keychain implementation using `/usr/bin/security` without secret argv."
  @behaviour Cuckoding.Security.SecretStore

  @service "com.cuckoding.secret"

  @impl true
  def put(reference, value, options) do
    args = ["add-generic-password", "-U", "-s", @service, "-a", reference, "-w"]
    run(args, value <> "\n", options)
  end

  @impl true
  def fetch(reference, options) do
    args = ["find-generic-password", "-s", @service, "-a", reference, "-w"]

    case runner(options).run("/usr/bin/security", args, "", options) do
      {:ok, output} -> {:ok, String.trim_trailing(output)}
      {:error, _status} -> {:error, :not_found}
    end
  end

  @impl true
  def delete(reference, options) do
    run(["delete-generic-password", "-s", @service, "-a", reference], "", options)
  end

  defp run(args, input, options) do
    case runner(options).run("/usr/bin/security", args, input, options) do
      {:ok, _output} -> :ok
      {:error, _status} -> {:error, :keychain_error}
    end
  end

  defp runner(options) do
    Keyword.get(options, :command_runner, Cuckoding.Security.PortCommandRunner)
  end
end

defmodule Cuckoding.Security.PortCommandRunner do
  @moduledoc false

  def run(executable, args, input, options \\ []) do
    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        args: args
      ])

    if input != "", do: Port.command(port, input)
    collect(port, "", Keyword.get(options, :timeout, 5_000))
  end

  defp collect(port, output, timeout) do
    receive do
      {^port, {:data, data}} -> collect(port, output <> data, timeout)
      {^port, {:exit_status, 0}} -> {:ok, output}
      {^port, {:exit_status, status}} -> {:error, status}
    after
      timeout ->
        Port.close(port)
        {:error, :timeout}
    end
  end
end
