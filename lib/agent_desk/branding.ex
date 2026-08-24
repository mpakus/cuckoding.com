defmodule AgentDesk.Branding do
  @moduledoc """
  User-facing product name. OTP modules stay `AgentDesk` / `AgentDeskWeb`.
  """

  @product_name "Cuckoding"
  @registry_docs "https://agentclientprotocol.com/get-started/registry"

  @spec product_name() :: String.t()
  def product_name, do: @product_name

  @spec registry_docs_url() :: String.t()
  def registry_docs_url, do: @registry_docs
end
