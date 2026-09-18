defmodule CuckodingWeb.UsageComponents do
  @moduledoc "Accessible usage and cost provenance labels."

  use CuckodingWeb, :html

  alias Cuckoding.Telemetry.Accounting

  attr :records, :list, required: true

  def usage_summary(assigns) do
    ~H"""
    <section aria-labelledby="usage-heading" class="space-y-3">
      <div>
        <h2 id="usage-heading" class="text-xl font-semibold text-slate-950">Recent usage</h2>
        <p class="text-sm text-slate-700">
          Provider cost is preferred. The ≈ symbol marks a versioned-catalog estimate.
        </p>
      </div>
      <p :if={@records == []} class="text-sm text-slate-700">No usage has been recorded.</p>
      <div :if={@records != []} class="overflow-x-auto rounded-lg border border-slate-200 bg-white">
        <table class="min-w-full divide-y divide-slate-200 text-left text-sm">
          <caption class="sr-only">Recent provider usage with cost source and confidence</caption>
          <thead class="bg-slate-50 text-slate-700">
            <tr>
              <th scope="col" class="px-4 py-3 font-semibold">Provider/model</th>
              <th scope="col" class="px-4 py-3 font-semibold">Token usage</th>
              <th scope="col" class="px-4 py-3 font-semibold">Cost</th>
              <th scope="col" class="px-4 py-3 font-semibold">Source</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-200">
            <tr :for={record <- @records} id={"usage-#{record.id}"}>
              <td class="px-4 py-3 text-slate-900">
                {record.provider}/{record.model || "Unknown model"}
              </td>
              <td class="px-4 py-3 text-slate-700">{token_usage(record)}</td>
              <td class="whitespace-nowrap px-4 py-3 font-medium text-slate-900">
                {Accounting.cost_label(record)}
              </td>
              <td class="whitespace-nowrap px-4 py-3 text-slate-700">
                {Accounting.cost_source_label(record)}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  defp token_usage(record) do
    [
      token_part(record.input_tokens, "in"),
      token_part(record.output_tokens, "out"),
      token_part(record.reasoning_tokens, "reasoning"),
      token_part(record.cache_read_tokens, "cache read"),
      token_part(record.cache_write_tokens, "cache write")
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> "Unavailable"
      parts -> Enum.join(parts, " · ")
    end
  end

  defp token_part(nil, _label), do: nil
  defp token_part(count, label), do: "#{count} #{label}"
end
