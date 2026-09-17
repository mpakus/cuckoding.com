defmodule Cuckoding.Execution.RunEventSequence do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:run_id, :string, autogenerate: false}
  schema "run_event_sequences" do
    field :last_sequence, :integer, default: 0
  end
end
