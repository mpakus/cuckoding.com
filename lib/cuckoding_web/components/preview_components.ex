defmodule CuckodingWeb.PreviewComponents do
  @moduledoc "Accessible preview status, link, and worktree actions."

  use CuckodingWeb, :html

  attr :preview_url, :string, required: true
  attr :health, :any, required: true
  attr :worktree_path, :string, required: true

  def preview_panel(assigns) do
    assigns = assign(assigns, :safe_preview_url, safe_preview_url(assigns.preview_url))

    ~H"""
    <section aria-labelledby="preview-heading" class="rounded-lg border border-slate-200 bg-white p-5">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 id="preview-heading" class="font-semibold text-slate-950">Preview</h2>
          <p class="mt-1 text-sm text-slate-700" role="status">{health_label(@health)}</p>
        </div>
        <a
          href={@safe_preview_url}
          target="_blank"
          rel="noopener noreferrer"
          class="rounded-md bg-slate-950 px-4 py-2 text-sm font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
        >
          Open preview
        </a>
      </div>
      <p class="mt-4 break-all font-mono text-xs text-slate-600">{@preview_url}</p>
      <div class="mt-4 flex flex-wrap gap-3" aria-label="Worktree actions">
        <button
          type="button"
          phx-click="open_worktree"
          phx-value-application="finder"
          class="rounded-md border border-slate-300 px-3 py-2 text-sm font-medium text-slate-900 focus-visible:outline-2 focus-visible:outline-offset-2"
        >
          Open in Finder
        </button>
        <button
          type="button"
          phx-click="open_worktree"
          phx-value-application="editor"
          class="rounded-md border border-slate-300 px-3 py-2 text-sm font-medium text-slate-900 focus-visible:outline-2 focus-visible:outline-offset-2"
        >
          Open in editor
        </button>
      </div>
      <p class="sr-only">Worktree: {@worktree_path}</p>
    </section>
    """
  end

  defp health_label(:healthy), do: "Healthy"
  defp health_label(:unavailable), do: "Unavailable"
  defp health_label({:unhealthy, status}), do: "Unhealthy · HTTP #{status}"
  defp health_label(_status), do: "Health unknown"

  defp safe_preview_url(url) do
    case URI.parse(url) do
      %URI{scheme: "http", host: "127.0.0.1", port: port, userinfo: nil}
      when is_integer(port) and port in 1_024..65_535 ->
        url

      _other ->
        "#"
    end
  end
end
