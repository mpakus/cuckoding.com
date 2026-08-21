defmodule AgentDesk.Containers.Fixture do
  @moduledoc false

  def main(args) do
    [action, name, directory, record] = Enum.take(args, 4)
    File.mkdir_p!(Path.dirname(record))

    File.write!(
      record,
      Jason.encode!(%{
        "action" => action,
        "name" => name,
        "directory" => directory
      })
    )
  end
end
