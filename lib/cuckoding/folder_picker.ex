defmodule Cuckoding.FolderPicker do
  @moduledoc "Opens the native macOS folder chooser for project registration."

  @cancelled "__CUCKODING_CANCELLED__"
  @script """
  try
    POSIX path of (choose folder with prompt "Choose a project folder")
  on error number -128
    return "#{@cancelled}"
  end try
  """

  def choose do
    case System.cmd("/usr/bin/osascript", ["-e", @script], stderr_to_stdout: true) do
      {output, 0} -> selected_path(output)
      {_output, _status} -> {:error, :folder_picker_failed}
    end
  end

  defp selected_path(output) do
    path = output |> String.trim_trailing("\n") |> String.trim_trailing("\r")

    case path do
      @cancelled -> :cancelled
      "" -> {:error, :folder_picker_failed}
      path -> {:ok, path}
    end
  end
end
