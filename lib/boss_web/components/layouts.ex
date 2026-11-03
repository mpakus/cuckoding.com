defmodule BossWeb.Layouts do
  use BossWeb, :html

  embed_templates "layouts/*"

  defp navigation_current(%{request_path: "/"}, :projects), do: "page"
  defp navigation_current(%{request_path: "/projects/" <> _}, :projects), do: "page"
  defp navigation_current(%{request_path: "/agents"}, :agents), do: "page"
  defp navigation_current(_, _), do: nil
end
