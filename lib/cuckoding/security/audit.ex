defmodule Cuckoding.Security.AuditEvent do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "security_audit_events" do
    field :event_type, :string
    field :method, :string
    field :path, :string
    field :status, :integer
    field :occurred_at, :utc_datetime_usec
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:id, :event_type, :method, :path, :status, :occurred_at])
    |> validate_required([:id, :event_type, :method, :path, :status, :occurred_at])
    |> validate_length(:path, max: 255)
  end
end

defmodule Cuckoding.Security.Audit do
  @moduledoc "Persists bounded authentication rejections without credentials or query strings."

  alias Cuckoding.Identifier
  alias Cuckoding.Repo
  alias Cuckoding.Security.AuditEvent

  @event_types ~w(auth.authorization_rejected auth.browser_token_rejected auth.loopback_boundary_rejected)
  @methods ~w(GET POST)

  def record(event_type, method, path, status)
      when event_type in @event_types and method in @methods and status in [401, 403] and
             is_binary(path) do
    %AuditEvent{}
    |> AuditEvent.changeset(%{
      id: Identifier.generate(),
      event_type: event_type,
      method: method,
      path: String.slice(path, 0, 255),
      status: status,
      occurred_at: Cuckoding.Clock.wall_now()
    })
    |> Repo.insert()
  end

  def record(_event_type, _method, _path, _status), do: {:error, :invalid_security_audit}
end
