defmodule Cuckoding.Plugins.Kinds.KnowledgeBackend do
  @moduledoc "Optional index and retrieval backend; Markdown remains authoritative."

  alias Cuckoding.Plugins.Context
  alias Cuckoding.Plugins.Result

  @callback index(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  @callback search(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  @callback recall(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  @callback write_candidate(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  @callback health(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
end

defmodule Cuckoding.Plugins.Kinds.ShellFilter do
  @moduledoc "Optional command wrapper and output filter; underlying commands stay policy-visible."

  alias Cuckoding.Plugins.Context
  alias Cuckoding.Plugins.Result

  @callback wrap(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  @callback filter(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  @callback analytics(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
end

defmodule Cuckoding.Plugins.Kinds.InstructionSkill do
  @moduledoc "Reviewed instruction package for a selected role or stage."

  alias Cuckoding.Plugins.Context
  alias Cuckoding.Plugins.Result

  @callback package(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
end

defmodule Cuckoding.Plugins.Kinds.McpServer do
  @moduledoc "Run-scoped MCP configuration with declared tools and permissions."

  alias Cuckoding.Plugins.Context
  alias Cuckoding.Plugins.Result

  @callback configuration(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
end

defmodule Cuckoding.Plugins.Kinds.Runner do
  @moduledoc "Plugin form of the RunnerBridge lifecycle."

  alias Cuckoding.Plugins.Context
  alias Cuckoding.Plugins.Result

  @callback prepare(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  @callback start(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  @callback exec(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  @callback pause(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  @callback hibernate(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  @callback resume(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  @callback inspect(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  @callback stream_events(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  @callback destroy(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
end

defmodule Cuckoding.Plugins.Kinds.MetricSource do
  @moduledoc "Optional metrics collector with explicit measurement provenance."

  alias Cuckoding.Plugins.Context
  alias Cuckoding.Plugins.Result

  @callback sample(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
end

defmodule Cuckoding.Plugins.Kinds.VcsHost do
  @moduledoc "Host-side VCS handoff boundary; credentials never enter an agent grant."

  alias Cuckoding.Plugins.Context
  alias Cuckoding.Plugins.Result

  @callback handoff(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
end

defmodule Cuckoding.Plugins.Kinds.SecretStore do
  @moduledoc "Host-owned secret reference boundary with private output kept out of public records."

  alias Cuckoding.Plugins.Context
  alias Cuckoding.Plugins.Result

  @callback put(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  @callback fetch(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  @callback delete(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
end

defmodule Cuckoding.Plugins.Kinds.Notifier do
  @moduledoc "Idempotently keyed notification delivery; notifications never decide approvals."

  alias Cuckoding.Plugins.Context
  alias Cuckoding.Plugins.Result

  @callback notify(map(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
end
