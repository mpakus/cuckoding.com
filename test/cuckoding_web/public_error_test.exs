defmodule CuckodingWeb.PublicErrorTest do
  use ExUnit.Case, async: true

  alias CuckodingWeb.PublicError

  test "formats validation messages without values or changeset internals" do
    changeset =
      {%{}, %{title: :string, priority: :integer}}
      |> Ecto.Changeset.cast(%{title: "", priority: 101}, [:title, :priority])
      |> Ecto.Changeset.validate_required([:title])
      |> Ecto.Changeset.validate_number(:priority, less_than_or_equal_to: 100)

    message = PublicError.changeset("Task could not be saved", changeset)

    assert message =~ "Task could not be saved."
    assert message =~ "Title can't be blank."
    assert message =~ "Priority must be less than or equal to 100."
    refute message =~ "%Ecto.Changeset"
    refute message =~ "valid?:"
  end

  test "unexpected failures contain only reviewed recovery copy" do
    assert PublicError.unexpected("Workflow could not start", "Open the run timeline and retry.") ==
             "Workflow could not start. Open the run timeline and retry."
  end

  test "LiveViews do not render inspected internal errors" do
    sources = Path.wildcard(Path.expand("../../lib/cuckoding_web/live/*.ex", __DIR__))

    assert sources != []

    for source <- sources do
      refute File.read!(source) =~ "inspect(", "internal error inspection in #{source}"
    end
  end
end
