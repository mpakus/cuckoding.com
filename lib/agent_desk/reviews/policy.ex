defmodule AgentDesk.Reviews.Policy do
  @moduledoc false

  @passed ~w(passed success ok)
  @failed ~w(failed error fail)

  @spec evaluate(map() | struct(), [map()]) :: map()
  def evaluate(project, checks) when is_list(checks) do
    checks = Enum.map(checks, &normalize/1)
    required = List.wrap(get_in(project.settings || %{}, ["required_checks"]))
    failed = for check <- checks, failed?(check), do: check.name
    missing = Enum.reject(required, &recorded_pass?(checks, &1))

    if failed == [] and missing == [] do
      %{status: "passed", failed: [], missing: []}
    else
      %{status: "failed", failed: failed, missing: missing}
    end
  end

  defp normalize(check) when is_map(check) do
    name = to_string(check[:name] || check["name"] || "check")
    status = check[:status] || check["status"] || "unknown"
    %{name: name, status: String.downcase(to_string(status))}
  end

  defp failed?(check), do: check.status in @failed

  defp recorded_pass?(checks, name) do
    Enum.any?(checks, fn check -> check.name == name and check.status in @passed end)
  end
end
