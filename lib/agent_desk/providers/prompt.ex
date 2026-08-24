defmodule AgentDesk.Providers.Prompt do
  @moduledoc """
  Turns user text plus attachments into provider-specific prompt payloads.
  """

  @max_inline_image 4_000_000

  @spec with_file_notes(String.t(), [map()]) :: String.t()
  def with_file_notes(text, attachments) when is_list(attachments) do
    notes =
      attachments
      |> Enum.reject(&image?/1)
      |> Enum.map_join("\n", fn att ->
        "- #{att["name"]}: #{att["path"]}"
      end)

    cond do
      notes == "" -> text || ""
      text in [nil, ""] -> "Attached files:\n" <> notes
      true -> String.trim(text) <> "\n\nAttached files:\n" <> notes
    end
  end

  @spec image?(map()) :: boolean()
  def image?(%{"mime" => mime}) when is_binary(mime), do: String.starts_with?(mime, "image/")
  def image?(_), do: false

  @spec images([map()]) :: [map()]
  def images(attachments), do: Enum.filter(attachments, &image?/1)

  @spec files([map()]) :: [map()]
  def files(attachments), do: Enum.reject(attachments, &image?/1)

  @spec names([map()]) :: [String.t()]
  def names(attachments), do: Enum.map(attachments, & &1["name"])

  @spec inline_image(map()) :: {:ok, String.t(), String.t()} | :error
  def inline_image(%{"path" => path, "mime" => mime} = att) when is_binary(path) do
    if image?(att) do
      case File.stat(path) do
        {:ok, %{size: size}} when size > 0 and size <= @max_inline_image ->
          case File.read(path) do
            {:ok, bytes} -> {:ok, mime, Base.encode64(bytes)}
            _ -> :error
          end

        _ ->
          :error
      end
    else
      :error
    end
  end

  def inline_image(_), do: :error
end
