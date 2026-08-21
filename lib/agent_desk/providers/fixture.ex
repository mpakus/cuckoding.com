defmodule AgentDesk.Providers.Fixture do
  @moduledoc false

  alias AgentDesk.Providers.CommandSpec

  @spec enabled?(keyword()) :: boolean()
  def enabled?(opts) do
    case Keyword.fetch(opts, :fixture) do
      {:ok, true} -> true
      {:ok, false} -> false
      {:ok, "true"} -> true
      _ -> Application.get_env(:agent_desk, :providers, [])[:use_fixtures] == true
    end
  end

  @spec command_spec(String.t(), keyword()) :: CommandSpec.t()
  def command_spec(protocol, opts \\ []) do
    extra = Keyword.get(opts, :peer_args, [])
    cwd = Keyword.get(opts, :cwd, File.cwd!())

    %CommandSpec{
      executable: elixir_executable(),
      args: code_path_args() ++ ["-e", eval(), "--", protocol] ++ extra,
      cwd: cwd,
      env: %{"AGENTDESK_FIXTURE" => "1"}
    }
  end

  defp elixir_executable do
    System.find_executable("elixir") || "elixir"
  end

  defp eval do
    "AgentDesk.Providers.Fixtures.StdioPeer.main(System.argv())"
  end

  defp code_path_args do
    for app <- [:jason, :agent_desk] do
      ["-pa", Application.app_dir(app, "ebin")]
    end
    |> List.flatten()
  end
end
