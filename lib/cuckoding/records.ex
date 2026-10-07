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

defmodule Cuckoding.TeamRevision do
  @moduledoc false
  use Ecto.Schema

  schema "team_revisions" do
    field :command_id, :binary_id
    field :definition, :map
    field :inserted_at, :utc_datetime_usec
  end
end

defmodule Cuckoding.Arena do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "arenas" do
    field :command_id, :binary_id
    field :selection_id, :binary_id
    belongs_to :team_revision, Cuckoding.TeamRevision
    field :name, :string
    field :path, :string
    field :device, :integer
    field :inode, :integer
    field :git_entry, :string
    field :inserted_at, :utc_datetime_usec
  end
end

defmodule Cuckoding.TeamAdoption do
  @moduledoc false
  use Ecto.Schema

  schema "team_adoptions" do
    field :arena_id, :binary_id
    field :tabula_id, :binary_id
    belongs_to :team_revision, Cuckoding.TeamRevision
    field :command_id, :binary_id
    field :inserted_at, :utc_datetime_usec
  end
end

defmodule Cuckoding.Tabula do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "tabulae" do
    belongs_to :arena, Cuckoding.Arena, type: :binary_id
    belongs_to :team_revision, Cuckoding.TeamRevision
    field :command_id, :binary_id
    field :name, :string
    field :definition, :map
    field :inserted_at, :utc_datetime_usec
  end
end

defmodule Cuckoding.DraftTask do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "draft_tasks" do
    belongs_to :tabula, Cuckoding.Tabula, type: :binary_id
    field :revision, :integer
    field :title, :string
    field :description, :string
    field :criteria, :string
    field :column, :string
    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Cuckoding.DraftTaskRevision do
  @moduledoc false
  use Ecto.Schema

  schema "draft_task_revisions" do
    field :task_id, :binary_id
    field :command_id, :binary_id
    field :revision, :integer
    field :content, :map
    field :inserted_at, :utc_datetime_usec
  end
end
