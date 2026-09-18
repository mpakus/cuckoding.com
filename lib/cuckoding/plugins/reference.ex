defmodule Cuckoding.Plugins.Reference.RTK do
  @moduledoc "RTK shell-filter adapter; command policy always sees the underlying command first."

  @behaviour Cuckoding.Plugins.Kinds.ShellFilter

  alias Cuckoding.Execution.CommandPolicy
  alias Cuckoding.Execution.Run
  alias Cuckoding.Plugins.Measurement
  alias Cuckoding.Plugins.Result
  alias Cuckoding.Repo
  alias Cuckoding.Telemetry.Accounting

  @impl true
  def wrap(%{"command_key" => command_key}, context) when is_binary(command_key) do
    with %Run{} = run <- Repo.get(Run, context.run_id),
         {:ok, command} <- CommandPolicy.resolve(run, command_key) do
      {:ok,
       %Result{
         data: %{
           "executable" => "rtk",
           "args" => [command.executable | command.args],
           "underlying_executable" => command.executable,
           "underlying_args" => command.args,
           "contribution" => "RTK output reduction",
           "source" => "configured"
         }
       }}
    else
      nil -> {:error, :run_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def wrap(_request, _context), do: {:error, :command_key_required}

  @impl true
  def filter(%{"streaming" => true}, _context) do
    {:ok, %Result{data: %{"mode" => "passthrough", "reason" => "streaming output required"}}}
  end

  def filter(_request, _context), do: {:ok, %Result{data: %{"mode" => "wrapped"}}}

  @impl true
  def analytics(request, context) do
    with {:ok, raw} <- non_negative_integer(request["raw_units"]),
         {:ok, optimized} <- non_negative_integer(request["optimized_units"]),
         true <- optimized <= raw,
         method when is_binary(method) and method != "" <- request["estimation_method"],
         {:ok, _record} <- record(context.run_id, raw, optimized, method) do
      measurements = [
        measurement("raw_units", raw),
        measurement("optimized_units", optimized),
        measurement("estimated_units_avoided", raw - optimized)
      ]

      {:ok,
       %Result{
         data: %{
           "contribution" => "Estimated shell-output tokens avoided",
           "source" => "estimated",
           "estimation_method" => method
         },
         measurements: measurements
       }}
    else
      false -> {:error, :invalid_optimization_units}
      nil -> {:error, :estimation_method_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp record(run_id, raw, optimized, method) do
    Accounting.record_optimization(%{
      run_id: run_id,
      plugin_key: "rtk",
      kind: "shell_output_tokens_avoided",
      raw_units: raw,
      optimized_units: optimized,
      confidence: "estimated",
      estimation_method: method,
      metadata_json: %{"filter_version" => "0.49.0"}
    })
  end

  defp measurement(name, value),
    do: %Measurement{name: name, value: value, unit: "tokens", source: "estimated"}

  defp non_negative_integer(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp non_negative_integer(_value), do: {:error, :invalid_optimization_units}
end

defmodule Cuckoding.Plugins.Reference.Ponytail do
  @moduledoc "Reviewed stage-scoped Ponytail instruction package with a mandatory safety overlay."

  @behaviour Cuckoding.Plugins.Kinds.InstructionSkill

  alias Cuckoding.Plugins.Result

  @modes ~w(lite full)
  @protected ~w(acceptance validation durability security privacy accessibility observability migration recovery verification)

  @impl true
  def package(request, %{stage_id: stage_id}) when is_binary(stage_id) do
    mode = Map.get(request, "mode", "full")

    with true <- mode in @modes,
         [] <- Map.get(request, "waive", []),
         {:ok, instructions} <- File.read(skill_path()) do
      {:ok,
       %Result{
         data: %{
           "mode" => mode,
           "instructions" => instructions,
           "policy_overlay" => @protected,
           "contribution" => "Ponytail #{mode} minimalism",
           "source" => "reviewed_instruction"
         }
       }}
    else
      false -> {:error, :invalid_ponytail_mode}
      [_waiver | _rest] -> {:error, :policy_overlay_refused}
      {:error, _reason} -> {:error, :ponytail_package_missing}
    end
  end

  def package(_request, _context), do: {:error, :ponytail_requires_stage_scope}

  defp skill_path, do: Application.app_dir(:cuckoding, "priv/plugins/ponytail/SKILL.md")
end

defmodule Cuckoding.Plugins.Reference.XERJ do
  @moduledoc "XERJ knowledge adapter with namespaces derived only from durable ownership."

  @behaviour Cuckoding.Plugins.Kinds.KnowledgeBackend

  alias Cuckoding.Execution.Run
  alias Cuckoding.Plugins.Result
  alias Cuckoding.Repo
  alias Cuckoding.Workflows.Board
  alias Cuckoding.Workflows.Task

  @maximum_query_bytes 4_096
  @maximum_results 10

  @impl true
  def index(%{"target" => target}, context) when target in ["worktree", "project"] do
    with {:ok, ownership} <- ownership(context.run_id) do
      path = if target == "worktree", do: "${RUN_WORKTREE}", else: "${PROJECT_REPO}"

      {:ok,
       result(ownership, "code", %{
         "command" => "xerj",
         "args" => ["autoindex", path, "--no-graph", "--prefix", code_namespace(ownership)],
         "contribution" => "XERJ lexical code index",
         "source" => "configured"
       })}
    end
  end

  def index(_request, _context), do: {:error, :invalid_xerj_index_target}

  @impl true
  def search(%{"query" => query} = request, context)
      when is_binary(query) and byte_size(query) in 1..@maximum_query_bytes do
    with {:ok, limit} <- limit(request),
         {:ok, ownership} <- ownership(context.run_id) do
      {:ok,
       result(ownership, "code", %{
         "command" => "xerj",
         "args" => [
           "search",
           "--prefix",
           code_namespace(ownership),
           "-k",
           to_string(limit),
           query
         ],
         "contribution" => "XERJ lexical search",
         "source" => "untrusted_retrieval"
       })}
    end
  end

  def search(_request, _context), do: {:error, :invalid_xerj_query}

  @impl true
  def recall(%{"query" => query}, context)
      when is_binary(query) and byte_size(query) in 1..@maximum_query_bytes do
    with {:ok, ownership} <- ownership(context.run_id) do
      {:ok,
       result(ownership, "memory", %{
         "namespace" => memory_namespace(ownership),
         "query" => query,
         "contribution" => "XERJ project memory recall",
         "source" => "untrusted_retrieval"
       })}
    end
  end

  def recall(_request, _context), do: {:error, :invalid_xerj_query}

  @impl true
  def write_candidate(%{"body" => body}, context) when is_binary(body) and body != "" do
    with {:ok, ownership} <- ownership(context.run_id) do
      {:ok,
       result(ownership, "candidate", %{
         "namespace" => "project:#{ownership.project_id}:candidate",
         "body" => body,
         "contribution" => "XERJ project candidate",
         "source" => "untrusted_candidate"
       })}
    end
  end

  def write_candidate(_request, _context), do: {:error, :invalid_xerj_candidate}

  @impl true
  def health(_request, context) do
    with {:ok, ownership} <- ownership(context.run_id) do
      {:ok,
       result(ownership, "health", %{
         "endpoint" => "http://127.0.0.1:9200",
         "mode" => "lexical",
         "contribution" => "XERJ local health",
         "source" => "configured"
       })}
    end
  end

  defp result(ownership, kind, data) do
    %Result{
      data: Map.merge(%{"namespace_kind" => kind, "project_id" => ownership.project_id}, data)
    }
  end

  defp ownership(run_id) do
    with %Run{} = run <- Repo.get(Run, run_id),
         %Task{} = task <- Repo.get(Task, run.task_id),
         %Board{} = board <- Repo.get(Board, task.board_id) do
      {:ok, %{project_id: board.project_id, board_id: board.id}}
    else
      nil -> {:error, :xerj_run_scope_not_found}
    end
  end

  defp limit(%{"limit" => limit}) when is_integer(limit) and limit in 1..@maximum_results,
    do: {:ok, limit}

  defp limit(%{"limit" => _limit}), do: {:error, :invalid_xerj_result_limit}
  defp limit(_request), do: {:ok, 5}
  defp code_namespace(ownership), do: "project:#{ownership.project_id}:code"
  defp memory_namespace(ownership), do: "project:#{ownership.project_id}:memory"
end

defmodule Cuckoding.Plugins.Reference.McpFilesystemReadonly do
  @moduledoc "Pinned official filesystem MCP configuration with a read-only tool allowlist."

  @behaviour Cuckoding.Plugins.Kinds.McpServer

  alias Cuckoding.Plugins.Result

  @package "@modelcontextprotocol/server-filesystem@2026.8.31"
  @integrity "sha512-kKaFkyAh6oipvc9+EAbJ552JafnMnOq5nzmzWkp1jJdBhTAAGpmIpWihUG1+rfNhmEFM98gUZDdCHCDD4v6a7Q=="
  @tools ~w(read_text_file read_media_file read_multiple_files list_directory list_directory_with_sizes directory_tree search_files get_file_info list_allowed_directories)

  @impl true
  def configuration(request, context) do
    tools = Map.get(request, "tools", @tools)

    with true <- is_list(tools) and Enum.uniq(tools) == tools,
         true <- Enum.all?(tools, &(&1 in @tools)),
         "none" <- context.network,
         [] <- context.permissions["write_paths"] do
      {:ok,
       %Result{
         data: %{
           "command" => "npx",
           "args" => ["--offline", "-y", @package, "${RUN_WORKTREE}"],
           "package" => @package,
           "integrity" => @integrity,
           "tools_allow" => tools,
           "contribution" => "Read-only worktree MCP tools",
           "source" => "pinned_package"
         }
       }}
    else
      false -> {:error, :mcp_tool_not_allowed}
      _grant -> {:error, :mcp_permission_mismatch}
    end
  end
end
