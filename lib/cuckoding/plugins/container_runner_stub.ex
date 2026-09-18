defmodule Cuckoding.Plugins.ContainerRunnerStub do
  @moduledoc "Non-selectable contract stub for future container runner backends."

  @behaviour Cuckoding.Plugins.Kinds.Runner

  alias Cuckoding.Plugins.Result

  @backends ~w(docker orbstack colima apple_containers)
  @operations ~w(prepare start exec pause hibernate resume inspect stream_events destroy)a

  for operation <- @operations do
    @impl true
    def unquote(operation)(request, _context) do
      backend = Map.get(request, "backend", "docker")

      if backend in @backends do
        {:ok,
         %Result{
           data: %{
             "backend" => backend,
             "operation" => Atom.to_string(unquote(operation)),
             "status" => "not_implemented",
             "git_strategy" => "host_side",
             "selectable" => false
           }
         }}
      else
        {:error, :unsupported_container_backend}
      end
    end
  end
end
