defmodule AgentDesk.Containers.Fixture do
  @moduledoc false

  def main(args) do
    [action, name, directory, record] = Enum.take(args, 4)
    File.mkdir_p!(Path.dirname(record))
    maybe_write_fixture_edit(action, directory)

    File.write!(
      record,
      Jason.encode!(%{
        "action" => action,
        "name" => name,
        "directory" => directory
      })
    )
  end

  defp maybe_write_fixture_edit("up", directory) do
    marker = Path.join(directory, ".agentdesk-compose-fixture-edit")

    if File.regular?(marker) do
      File.write!(Path.join(directory, "compose-created.txt"), "created by compose fixture\n")
    end
  end

  defp maybe_write_fixture_edit(_action, _directory), do: :ok
end
