defmodule CuckodingShellSpike.Application do
  use Application

  @impl true
  def start(_type, _args) do
    if System.get_env("CUCKODING_CRASH_BEFORE_READY") == "1", do: :erlang.halt(41)
    port = System.fetch_env!("CUCKODING_PORT") |> String.to_integer()

    children = [
      CuckodingShellSpike.Auth,
      {Phoenix.PubSub, name: CuckodingShellSpike.PubSub},
      CuckodingShellSpike.Endpoint
    ]

    with {:ok, supervisor} <- Supervisor.start_link(children, strategy: :one_for_one) do
      IO.puts(~s(READY {"port":#{port},"version":"0.1.0"}))
      {:ok, supervisor}
    end
  end
end
