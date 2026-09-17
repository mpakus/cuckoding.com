defmodule Cuckoding.Correlation do
  @moduledoc """
  Propagates public correlation identifiers through Logger and telemetry metadata.
  """

  def put(id) when is_binary(id) and byte_size(id) > 0 do
    Logger.metadata(correlation_id: id)
    id
  end

  def current, do: Logger.metadata()[:correlation_id]

  def capture, do: %{correlation_id: current()}

  def with_context(context, callback) when is_map(context) and is_function(callback, 0) do
    previous = Logger.metadata()

    try do
      Logger.metadata(correlation_id: context[:correlation_id])
      callback.()
    after
      Logger.reset_metadata(previous)
    end
  end

  def telemetry_metadata(metadata \\ %{}) when is_map(metadata) do
    Map.put_new(metadata, :correlation_id, current())
  end

  def execute(event, measurements, metadata \\ %{}) do
    :telemetry.execute(event, measurements, telemetry_metadata(metadata))
  end
end
