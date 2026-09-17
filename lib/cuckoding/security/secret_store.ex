defmodule Cuckoding.Security.SecretStore do
  @moduledoc "Stores raw values behind opaque references and audits successful reads."

  alias Cuckoding.Identifier
  alias Cuckoding.Repo
  alias Cuckoding.Security.SecretAccessAudit

  @callback put(String.t(), String.t(), keyword()) :: :ok | {:error, atom()}
  @callback fetch(String.t(), keyword()) :: {:ok, String.t()} | {:error, atom()}
  @callback delete(String.t(), keyword()) :: :ok | {:error, atom()}

  def put(value, options \\ []) when is_binary(value) and byte_size(value) > 0 do
    reference = "keychain:" <> Identifier.generate()

    case implementation().put(reference, value, options) do
      :ok -> {:ok, reference}
      {:error, reason} -> {:error, reason}
    end
  end

  def fetch(reference, purpose, options \\ [])
      when is_binary(reference) and is_binary(purpose) and purpose != "" do
    with {:ok, value} <- implementation().fetch(reference, options),
         {:ok, _audit} <- audit(reference, purpose, options) do
      {:ok, value}
    end
  end

  def delete(reference, options \\ []) when is_binary(reference),
    do: implementation().delete(reference, options)

  defp audit(reference, purpose, options) do
    attrs = %{
      id: Identifier.generate(),
      secret_ref: reference,
      purpose: purpose,
      run_id: Keyword.get(options, :run_id),
      occurred_at: Keyword.get(options, :now, Cuckoding.Clock.wall_now())
    }

    SecretAccessAudit |> struct() |> SecretAccessAudit.changeset(attrs) |> Repo.insert()
  end

  defp implementation do
    Application.get_env(:cuckoding, :secret_store, Cuckoding.Security.KeychainSecretStore)
  end
end

defmodule Cuckoding.Security.SecretAccessAudit do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "secret_access_audits" do
    field :secret_ref, :string
    field :purpose, :string
    field :run_id, :binary_id
    field :occurred_at, :utc_datetime_usec
  end

  def changeset(audit, attrs) do
    audit
    |> cast(attrs, [:id, :secret_ref, :purpose, :run_id, :occurred_at])
    |> validate_required([:id, :secret_ref, :purpose, :occurred_at])
  end
end
