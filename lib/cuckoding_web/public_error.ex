defmodule CuckodingWeb.PublicError do
  @moduledoc "Formats safe, stable validation and fallback messages for the browser UI."

  def changeset(action, %Ecto.Changeset{} = changeset) when is_binary(action) do
    details =
      changeset.errors
      |> Enum.take(3)
      |> Enum.map_join(" ", fn {field, error} ->
        "#{field_label(field)} #{error_message(error)}."
      end)

    if details == "",
      do: "#{action}. Review the fields and try again.",
      else: "#{action}. #{details}"
  end

  def unexpected(action, next_step) when is_binary(action) and is_binary(next_step),
    do: "#{action}. #{next_step}"

  defp field_label(field),
    do: field |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp error_message({message, options}) do
    Enum.reduce(options, message, fn {key, value}, text ->
      String.replace(text, "%{#{key}}", safe_value(value))
    end)
  end

  defp safe_value(value) when is_integer(value), do: Integer.to_string(value)
  defp safe_value(value) when is_atom(value), do: Atom.to_string(value)
  defp safe_value(_value), do: "the allowed value"
end
