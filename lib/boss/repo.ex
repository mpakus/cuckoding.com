defmodule Boss.Repo do
  use Ecto.Repo,
    otp_app: :boss,
    adapter: Ecto.Adapters.SQLite3
end
