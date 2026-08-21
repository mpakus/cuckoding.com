defmodule AgentDesk.Ids do
  @moduledoc """
  UUID generator for durable externally referenced entities.
  """

  @spec generate() :: Ecto.UUID.t()
  def generate do
    Ecto.UUID.generate()
  end
end
