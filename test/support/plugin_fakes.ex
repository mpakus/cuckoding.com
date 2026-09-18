defmodule Cuckoding.PluginFakes do
  @moduledoc false

  alias Cuckoding.Plugins.Measurement
  alias Cuckoding.Plugins.Result

  def reply(kind, operation, context, data \\ %{}, measurements \\ []) do
    send(self(), {:plugin_fake_called, kind, operation, context.run_id})

    {:ok,
     %Result{
       data: Map.merge(%{"kind" => kind, "operation" => Atom.to_string(operation)}, data),
       measurements: measurements
     }}
  end

  def measurement(name, value, unit, source),
    do: %Measurement{name: name, value: value, unit: unit, source: source}
end

defmodule Cuckoding.PluginFakes.KnowledgeBackend do
  @moduledoc false
  @behaviour Cuckoding.Plugins.Kinds.KnowledgeBackend

  @impl true
  def index(_request, context), do: reply(:index, context)
  @impl true
  def search(_request, context), do: reply(:search, context)
  @impl true
  def recall(_request, context), do: reply(:recall, context)
  @impl true
  def write_candidate(_request, context), do: reply(:write_candidate, context)
  @impl true
  def health(_request, context), do: reply(:health, context, %{"status" => "available"})

  defp reply(operation, context, data \\ %{}),
    do: Cuckoding.PluginFakes.reply("knowledge_backend", operation, context, data)
end

defmodule Cuckoding.PluginFakes.ShellFilter do
  @moduledoc false
  @behaviour Cuckoding.Plugins.Kinds.ShellFilter

  @impl true
  def wrap(_request, context), do: reply(:wrap, context)
  @impl true
  def filter(_request, context), do: reply(:filter, context, %{"output" => "filtered"})

  @impl true
  def analytics(_request, context) do
    measurement = Cuckoding.PluginFakes.measurement("saved_units", 12, "tokens", "estimated")
    Cuckoding.PluginFakes.reply("shell_filter", :analytics, context, %{}, [measurement])
  end

  defp reply(operation, context, data \\ %{}),
    do: Cuckoding.PluginFakes.reply("shell_filter", operation, context, data)
end

defmodule Cuckoding.PluginFakes.InstructionSkill do
  @moduledoc false
  @behaviour Cuckoding.Plugins.Kinds.InstructionSkill

  @impl true
  def package(_request, context) do
    Cuckoding.PluginFakes.reply("instruction_skill", :package, context, %{
      "path" => "SKILL.md"
    })
  end
end

defmodule Cuckoding.PluginFakes.McpServer do
  @moduledoc false
  @behaviour Cuckoding.Plugins.Kinds.McpServer

  @impl true
  def configuration(_request, context) do
    Cuckoding.PluginFakes.reply("mcp_server", :configuration, context, %{
      "command" => "fake-mcp",
      "tools" => ["search"]
    })
  end
end

defmodule Cuckoding.PluginFakes.Runner do
  @moduledoc false
  @behaviour Cuckoding.Plugins.Kinds.Runner

  for operation <- [
        :prepare,
        :start,
        :exec,
        :pause,
        :hibernate,
        :resume,
        :inspect,
        :stream_events,
        :destroy
      ] do
    @impl true
    def unquote(operation)(_request, context) do
      Cuckoding.PluginFakes.reply("runner", unquote(operation), context, %{
        "state" => Atom.to_string(unquote(operation))
      })
    end
  end
end

defmodule Cuckoding.PluginFakes.MetricSource do
  @moduledoc false
  @behaviour Cuckoding.Plugins.Kinds.MetricSource

  @impl true
  def sample(_request, context) do
    measurement = Cuckoding.PluginFakes.measurement("memory", 256, "bytes", "measured")
    Cuckoding.PluginFakes.reply("metric_source", :sample, context, %{}, [measurement])
  end
end

defmodule Cuckoding.PluginFakes.VcsHost do
  @moduledoc false
  @behaviour Cuckoding.Plugins.Kinds.VcsHost

  @impl true
  def handoff(_request, context) do
    Cuckoding.PluginFakes.reply("vcs_host", :handoff, context, %{"status" => "proposed"})
  end
end

defmodule Cuckoding.PluginFakes.SecretStore do
  @moduledoc false
  @behaviour Cuckoding.Plugins.Kinds.SecretStore

  alias Cuckoding.Plugins.Result

  @impl true
  def put(_request, context), do: reply(:put, context)

  @impl true
  def fetch(_request, context) do
    send(self(), {:plugin_fake_called, "secret_store", :fetch, context.run_id})
    {:ok, %Result{data: %{"reference" => "fake:secret"}, private: %{"value" => "fixture"}}}
  end

  @impl true
  def delete(_request, context), do: reply(:delete, context)

  defp reply(operation, context),
    do: Cuckoding.PluginFakes.reply("secret_store", operation, context)
end

defmodule Cuckoding.PluginFakes.Notifier do
  @moduledoc false
  @behaviour Cuckoding.Plugins.Kinds.Notifier

  @impl true
  def notify(_request, context) do
    Cuckoding.PluginFakes.reply("notifier", :notify, context, %{"status" => "delivered"})
  end
end
