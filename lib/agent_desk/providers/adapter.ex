defmodule AgentDesk.Providers.Adapter do
  @moduledoc """
  Behaviour every first-class provider adapter implements.
  """

  alias AgentDesk.Agents.Session
  alias AgentDesk.Providers.Capabilities
  alias AgentDesk.Providers.CommandSpec
  alias AgentDesk.Providers.Event

  @type decode_state :: term()
  @type action ::
          :initialize
          | :initialized
          | {:start_session, String.t()}
          | {:resume, String.t()}
          | {:prompt, String.t()}
          | :interrupt
          | {:approve, String.t(), String.t()}
          | {:configure_mcp, String.t()}
          | {:reject_method, term(), String.t()}

  @callback key() :: String.t()
  @callback display_name() :: String.t()
  @callback capabilities() :: Capabilities.t()
  @callback probe(keyword()) :: {:ok, map()} | {:error, term()}
  @callback command_spec(Session.t(), keyword()) :: {:ok, CommandSpec.t()} | {:error, term()}
  @callback init_decode() :: decode_state()
  @callback decode_line(String.t(), decode_state()) ::
              {:ok, [Event.t()], decode_state()} | {:error, term()}
  @callback encode(action(), decode_state()) ::
              {:ok, iodata(), decode_state()} | {:error, term()}
end
