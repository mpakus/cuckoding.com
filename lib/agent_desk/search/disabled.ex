defmodule AgentDesk.Search.Disabled do
  @moduledoc """
  Search adapter used when XERJ is off or unhealthy.
  """

  @behaviour AgentDesk.Search.Adapter

  @impl true
  def health(_ctx), do: {:error, :unavailable}

  @impl true
  def index_project(_project), do: {:error, :unavailable}

  @impl true
  def index_documents(_project, _docs), do: {:error, :unavailable}

  @impl true
  def search(_project, _query), do: {:error, :unavailable}

  @impl true
  def remember(_namespace, _memory), do: {:error, :unavailable}

  @impl true
  def recall(_namespace, _query), do: {:error, :unavailable}

  @impl true
  def forget(_namespace, _id), do: {:error, :unavailable}

  @impl true
  def rebuild(_project), do: {:error, :unavailable}

  @impl true
  def purge(_project), do: :ok
end
