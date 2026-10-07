defmodule Cuckoding.Workspace do
  @moduledoc false
  use Ecto.Schema

  schema "workspace" do
    field :revision, :integer
    field :tools, :map
    field :codex, :map, default: %{}
    field :connection, :map, default: %{}
    field :checked_at, :utc_datetime_usec
  end
end

defmodule Cuckoding.Command do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "commands" do
    field :kind, :string
    field :payload, :map, default: %{}
    field :expected_revision, :integer
    field :state, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :lease_until, :integer
    field :result, :string
    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Cuckoding.Event do
  @moduledoc false
  use Ecto.Schema

  schema "events" do
    field :command_id, :binary_id
    field :kind, :string
    field :data, :map, default: %{}
    field :occurred_at, :utc_datetime_usec
  end
end

defmodule Cuckoding.BrowserToken do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:digest, :binary, autogenerate: false}
  schema "browser_tokens" do
    field :kind, :string
    field :expires_at, :integer
  end
end
