defmodule Cuckoding.FakeSecretStore do
  @moduledoc false
  @behaviour Cuckoding.Security.SecretStore

  @table :cuckoding_fake_secrets

  def reset do
    if :ets.whereis(@table) != :undefined, do: :ets.delete(@table)
    :ets.new(@table, [:named_table, :public, :set])
    :ok
  end

  @impl true
  def put(reference, value, _options) do
    true = :ets.insert(@table, {reference, value})
    :ok
  end

  @impl true
  def fetch(reference, _options) do
    case :ets.lookup(@table, reference) do
      [{^reference, value}] -> {:ok, value}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def delete(reference, _options) do
    :ets.delete(@table, reference)
    :ok
  end
end

defmodule Cuckoding.FakeCommandRunner do
  @moduledoc false

  def run(executable, args, input, options) do
    send(Keyword.fetch!(options, :owner), {:command, executable, args, input})
    Keyword.get(options, :result, {:ok, ""})
  end
end
