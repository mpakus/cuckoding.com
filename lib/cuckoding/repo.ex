defmodule Cuckoding.Repo do
  use Ecto.Repo,
    otp_app: :cuckoding,
    adapter: Ecto.Adapters.SQLite3
end
