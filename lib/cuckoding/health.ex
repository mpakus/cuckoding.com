defmodule Cuckoding.Health do
  @moduledoc """
  Small runtime health projection shared by JSON and LiveView status surfaces.
  """

  def snapshot do
    application = process_status(Cuckoding.Supervisor)

    dependencies = %{
      pubsub: process_status(Cuckoding.PubSub),
      web_endpoint: process_status(CuckodingWeb.Endpoint)
    }

    %{
      status: overall_status(application, dependencies),
      generated_at: Cuckoding.Clock.wall_now(),
      application: %{
        name: :cuckoding,
        version: Application.spec(:cuckoding, :vsn) |> to_string(),
        status: application
      },
      dependencies: dependencies
    }
  end

  def overall_status(:ok, dependencies) do
    if Enum.all?(dependencies, fn {_name, status} -> status == :ok end),
      do: :ok,
      else: :degraded
  end

  def overall_status(_application, _dependencies), do: :degraded

  defp process_status(name) do
    if Process.whereis(name), do: :ok, else: :unavailable
  end
end
