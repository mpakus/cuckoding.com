defmodule Boss.Projects.TaskPrompt do
  @moduledoc """
  Natural-language task creation and control on a project workspace.

  Runs the selected execution agent in read-only `:task_prompt` mode against the
  project's repository and current task snapshot, validates a bounded structured
  JSON action plan (`priv/task_prompt_schema.json`), and applies each allowed
  action through BOSS's existing persistence and workflow APIs.
  """
  import Ecto.Query

  alias Boss.{Deliveries, Projects, Repo, Runs, Tasks}
  alias Boss.Agents.{Cursor, Metadata}
  alias Boss.Deliveries.{Delivery, Queue, Request, Worker}
  alias Boss.Projects.{Documentation, Project, Repository, Spec, SpecDocument, SpecRevision}
  alias Boss.Tasks.{Revisions, Task}

  @max_prompt_bytes 8_000
  @max_check_bytes 4_096
  @max_report_bytes 32_768
  @max_actions 16
  @max_context_bytes 98_304
  @timeout_ms 180_000

  @top_keys ~w(actions summary)
  @action_keys ~w(acceptance depends_on op reason specification task_ref title)
  @ops ~w(
    create_task
    update_task_spec
    add_task_note
    block_task
    needs_input_task
    cancel_task
    resume_task
    retry_task
    start_workflow
    queue_workflow
    cancel_queued_workflow
    stop_workflow
  )
  @active_delivery_statuses ~w(planning implementing testing reviewing integrating)
  @active_run_statuses ~w(preparing launching running stopping)

  def run(project_id, request_id, params, opts \\ []) do
    with :ok <- validate_request(project_id, request_id, params),
         {:ok, project} <- fetch_project(project_id),
         :ok <- validate_root_directory(project.root_path),
         :ok <- claim_active(project_id, request_id) do
      try do
        execute_prompt(project, params, opts)
      after
        release_active(project_id, request_id)
      end
    end
  end

  def stop(project_id, request_id)
      when is_integer(project_id) and project_id > 0 and is_binary(request_id) do
    case :ets.lookup(active_table(), project_id) do
      [{^project_id, ^request_id, pid}] when is_pid(pid) ->
        if Process.alive?(pid), do: send(pid, :stop)
        :ok

      _ ->
        :ok
    end
  end

  def stop(_, _), do: :ok

  def active?(project_id) when is_integer(project_id) and project_id > 0 do
    case :ets.lookup(active_table(), project_id) do
      [{^project_id, _id, pid}] when is_pid(pid) -> Process.alive?(pid)
      _ -> false
    end
  end

  def active?(_), do: false

  @doc false
  def decode(text) when is_binary(text) do
    cond do
      String.trim(text) == "" ->
        {:error, :report_empty}

      byte_size(text) > @max_report_bytes ->
        {:error, :report_too_large}

      not String.valid?(text) or String.contains?(text, <<0>>) ->
        {:error, :invalid_encoding}

      true ->
        extracted = Cursor.extract_json_or_raw(text)

        if byte_size(extracted) > @max_report_bytes do
          {:error, :report_too_large}
        else
          decode_object(extracted)
        end
    end
  end

  def decode(_), do: {:error, :invalid_shape}

  @doc false
  def apply_report(project_id, report, exec_opts \\ %{})
      when is_integer(project_id) and is_map(report) do
    with {:ok, project} <- fetch_project(project_id) do
      snapshot = load_tasks_snapshot(project.id)
      ref_map = build_ref_map(snapshot)
      actions = Map.get(report, "actions", [])

      {results, _ref_map, mutated?} =
        Enum.reduce(actions, {[], ref_map, false}, fn action, {acc, refs, changed?} ->
          {outcome, next_refs, did_change?} =
            apply_action(project, action, refs, exec_opts)

          {[outcome | acc], next_refs, changed? or did_change?}
        end)

      if mutated? do
        Tasks.broadcast(project.id)
      end

      {:ok,
       %{
         summary: sanitize_multiline(Map.get(report, "summary", ""), 1_200),
         results: Enum.reverse(results)
       }}
    end
  end

  def message(:invalid_prompt),
    do: "Enter a non-empty prompt of at most 8,000 UTF-8 bytes."

  def message(:invalid_agent),
    do: "Choose Codex, Claude Code, Cursor Agent, or OpenCode."

  def message(:invalid_reviewer),
    do: "Choose Codex, Claude Code, Cursor Agent, or OpenCode as the independent reviewer."

  def message(:invalid_check_command),
    do: "Check command must be at most 4,096 UTF-8 bytes."

  def message(:project_not_found),
    do: "This project is no longer available."

  def message(:invalid_repository),
    do: "The project's repository directory could not be accessed."

  def message(:busy),
    do: "Another prompt request is already running for this project. Wait or choose Stop."

  def message(:cancelled),
    do: "Prompt execution stopped."

  def message(:cleanup_unknown),
    do: "The agent stopped without a confirmed process-group cleanup receipt."

  def message(:codex_unavailable), do: "Codex is unavailable on BOSS's PATH."
  def message(:claude_unavailable), do: "Claude Code is unavailable on BOSS's PATH."
  def message(:cursor_unavailable), do: "Cursor Agent is unavailable on BOSS's PATH."
  def message(:opencode_unavailable), do: "OpenCode is unavailable on BOSS's PATH."

  def message(:provider_auth),
    do: "The selected agent could not authenticate. Check its status on the Agents page."

  def message(:provider_rate_limit),
    do: "The selected agent reported a rate, quota, or credit limit."

  def message(:timeout),
    do: "The prompt agent timed out before returning an action plan."

  def message({:agent_failed, reason}) when is_binary(reason) and reason != "",
    do: reason

  def message(_),
    do: "The agent did not return a valid task action plan. Refine the prompt and try again."

  # --- Execution ---

  defp execute_prompt(project, params, opts) do
    snapshot = load_tasks_snapshot(project.id)
    check_text = String.trim(Map.get(params, :check_command, "") || "")

    reviewer =
      Map.get(params, :reviewer) || Boss.Projects.RoleBindings.reviewer_agent(project.id)

    agent = Map.fetch!(params, :agent)

    model_id =
      case Map.get(params, :model_id) do
        val when is_binary(val) ->
          trimmed = String.trim(val)
          if trimmed in ["", "__default__"], do: nil, else: trimmed

        _ ->
          nil
      end

    reasoning_effort =
      case Map.get(params, :reasoning_effort) do
        val when is_binary(val) ->
          trimmed = String.trim(val)
          if trimmed in ["", "default"], do: nil, else: trimmed

        _ ->
          nil
      end

    prompt_role =
      case Map.get(params, :prompt_role) do
        "reviewer" -> "reviewer"
        _ -> "analytic"
      end

    selection =
      if model_id do
        %{model_id: model_id, reasoning_effort: reasoning_effort}
      else
        Boss.Agents.Roles.selection_for(prompt_role, agent, project.id)
      end

    prompt_text =
      build_prompt(project, snapshot, params.prompt, check_text, reviewer, prompt_role)

    runner =
      case Keyword.get(opts, :runner) do
        nil -> fn a, p, pr, dl -> default_runner(a, p, pr, dl, selection) end
        fun when is_function(fun, 5) -> fn a, p, pr, dl -> fun.(a, p, pr, dl, selection) end
        fun when is_function(fun, 4) -> fun
      end

    deadline = System.monotonic_time(:millisecond) + Keyword.get(opts, :timeout_ms, @timeout_ms)

    case safe_invoke_runner(runner, agent, project.root_path, prompt_text, deadline) do
      %{"status" => "finished", "cleanup" => "group_empty", "report" => report} ->
        apply_report(project.id, report, %{
          check_command: check_text,
          reviewer: reviewer,
          agent: agent,
          model_id: selection[:model_id],
          server: Keyword.get(opts, :server, Boss.Runs.Manager)
        })

      %{"status" => "cancelled"} ->
        {:error, :cancelled}

      %{"cleanup" => "unknown"} ->
        {:error, :cleanup_unknown}

      %{"outcome" => "timed_out"} ->
        {:error, :timeout}

      %{"summary" => %{"error_class" => "auth"}} ->
        {:error, :provider_auth}

      %{"summary" => %{"error_class" => "rate_limit"}} ->
        {:error, :provider_rate_limit}

      %{"reason" => reason} when is_binary(reason) and reason != "" ->
        {:error, {:agent_failed, sanitize_single_line(reason, 280)}}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, :invalid_report}
    end
  end

  defp default_runner(agent, path, prompt, deadline, selection) do
    Worker.run_agent(:task_prompt, path, prompt, &decode/1, nil,
      implementer: agent,
      selection: selection,
      report_diagnostics: true,
      deadline_ms: deadline
    )
  end

  defp safe_invoke_runner(runner, agent, path, prompt, deadline) do
    receive do
      :stop -> {:error, :cancelled}
    after
      0 -> runner.(agent, path, prompt, deadline)
    end
  catch
    :throw, {:halt, reason} -> {:error, reason}
  end

  # --- Prompt Construction ---

  @doc false
  def build_prompt(
        project,
        snapshot,
        user_prompt,
        check_text,
        reviewer,
        prompt_role \\ "analytic"
      ) do
    workflow_ready? = match?({:ok, _, _}, Boss.Checks.Command.parse_workflow(check_text))

    verification_mode =
      if String.trim(check_text || "") == "",
        do: "spec_only (Reviewer verifies against task specification)",
        else: "command (#{String.trim(check_text)}) + Reviewer"

    role_title =
      if prompt_role == "reviewer",
        do: "Reviewer specification auditor & task controller",
        else: "Analytic documentation planner & task controller"

    tasks_json = encode_tasks_context(snapshot, user_prompt)
    docs_index = build_docs_index(project)

    """
    You are BOSS's read-only #{role_title} for project #{JSON.encode!(project.name)}.
    Convert the owner's prompt into a valid JSON object matching the required schema (`summary` and `actions`), or answer their question with `"actions": []`.

    Project metadata:
    - project_id: #{project.id}
    - intake_mode: #{project.intake_mode}
    - docs_or_specs_directory: #{project.specs_path}
    - base_branch: #{project.base_branch || "HEAD"}
    - workflow_check_configured: #{workflow_ready?}
    - workflow_verification_mode: #{verification_mode}
    - workflow_reviewer: #{reviewer}

    Execution speed & safety rules:
    1. Return ONLY one compact JSON object (UTF-8, <= 32768 bytes) with exact top-level keys `"summary"` and `"actions"` (0..16 items) and exact item keys `"op"`, `"task_ref"`, `"title"`, `"specification"`, `"acceptance"`, `"depends_on"`, `"reason"`. Unused fields on an item MUST be `null`.
    2. For board/state/workflow control prompts or status questions, answer directly from the task snapshot below without scanning repository files. When creating tasks from `docs/` or refining specifications (`create_task` or `update_task_spec`), inspect the relevant Markdown files listed in `Documentation / specs directory index` below so task titles, `depends_on` DAG edges, and measurable `acceptance` criteria match the real documentation.
    3. Allowed `op` values and rules:
       - `"create_task"`: Create a new Backlog (`new`) task. `task_ref` MUST be a new unique lowercase slug matching `^[a-z][a-z0-9_-]{0,63}$`. Provide single-line `title` (1..200 chars), concise Markdown `specification` (1..8000 bytes), `acceptance` (1..12 measurable criteria strings), `depends_on` (array of explicit task IDs, or `[]`), and `reason: null`.
       - `"update_task_spec"`: Enrich, supplement, or update a task's specification (recording a new immutable revision and adopting it when idle, returning blocked/needs_input tasks cleanly to Backlog `new`). `task_ref` is the existing task's `explicit_id` (preferred) or string `task_id`. Provide full updated `title`, `specification`, `acceptance`, `depends_on`, and `reason: null`.
       - `"add_task_note"`: Leave an Analytic/Reviewer comment, clarification note, or log entry on a task's history without changing its state. Set `task_ref` and nonblank `reason` (1..1000 bytes); all spec fields `null`.
       - `"block_task"`: Move an idle task (`state` not `done` and `has_active_workflow: false`) to `blocked`. Set `task_ref` and nonblank `reason`; other fields `null`.
       - `"needs_input_task"`: Move an idle task to `needs_input` with a specific question/reason in `reason`; other fields `null`.
       - `"cancel_task"`: Cancel an unfinished task (`has_active_workflow: false`) with nonblank `reason`; other fields `null`.
       - `"resume_task"`: Resume a `blocked` or `needs_input` task (`recovery_state: "new"`) or a paused queued workflow; `reason: null` and spec fields `null`.
       - `"retry_task"`: Reset a `failed`, `interrupted`, or `cancelled` task with `recovery_state: "new"` back to `new`; `reason: null` and spec fields `null`. (To re-run a failed/blocked/cancelled task through an agent workflow, use `"start_workflow"` or `"queue_workflow"` instead.)
       - `"start_workflow"`: Start BOSS's managed delivery workflow on an eligible unfinished task (`state` in `new`, `failed`, `interrupted`, `cancelled`, `blocked`, `needs_input` with satisfied dependencies). All fields except `op` and `task_ref` MUST be `null`.
       - `"queue_workflow"`: Queue BOSS's managed delivery workflow on an eligible unfinished task (even if dependencies are not yet `done`). All fields except `op` and `task_ref` MUST be `null`.
       - `"cancel_queued_workflow"`: Cancel a pending/paused queued workflow (`has_queued_workflow: true`). All fields except `op` and `task_ref` MUST be `null`.
       - `"stop_workflow"`: Stop an active running workflow (`has_active_workflow: true`). All fields except `op` and `task_ref` MUST be `null`.
    4. Never attempt to mark a task `done` or `approved` directly; BOSS requires commit-bound delivery and independent Reviewer verification via `start_workflow`, `queue_workflow`, or `Start Autopilot`.

    Documentation / specs directory index (#{project.specs_path}):
    #{docs_index}

    Current project tasks (non-reference):
    #{tasks_json}

    Owner prompt:
    #{user_prompt}
    """
  end

  defp build_docs_index(project) do
    with {:ok, specs_root} <- Repository.specs_directory(project.root_path, project.specs_path) do
      files =
        collect_markdown_files(specs_root, "", 0, [])
        |> Enum.sort()
        |> Enum.take(40)

      if files == [] do
        "(no Markdown files found yet)"
      else
        files
        |> Enum.map_join("\n", fn rel ->
          full = Path.join(specs_root, rel)
          outline = extract_heading_outline(full)
          if outline == "", do: "- #{rel}", else: "- #{rel} — #{outline}"
        end)
        |> Cursor.clip_utf8(8_000)
      end
    else
      _ -> "(unavailable)"
    end
  rescue
    _ -> "(unavailable)"
  end

  defp collect_markdown_files(_root, _rel, depth, acc) when depth > 5 or length(acc) >= 48,
    do: acc

  defp collect_markdown_files(root, rel_dir, depth, acc) do
    dir = if rel_dir == "", do: root, else: Path.join(root, rel_dir)

    case File.ls(dir) do
      {:ok, names} ->
        names
        |> Enum.sort()
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.reduce(acc, fn name, list ->
          if length(list) >= 48 do
            list
          else
            rel = if rel_dir == "", do: name, else: Path.join(rel_dir, name)
            full = Path.join(root, rel)

            case File.lstat(full) do
              {:ok, %{type: :regular}} ->
                if String.ends_with?(String.downcase(name), ".md"),
                  do: [rel | list],
                  else: list

              {:ok, %{type: :directory}} ->
                collect_markdown_files(root, rel, depth + 1, list)

              _ ->
                list
            end
          end
        end)

      _ ->
        acc
    end
  end

  defp extract_heading_outline(path) do
    case File.open(path, [:read, :raw], fn io -> :file.read(io, 2_048) end) do
      {:ok, {:ok, bin}} when is_binary(bin) ->
        if String.valid?(bin) do
          bin
          |> String.split(~r/\r?\n/)
          |> Enum.filter(&Regex.match?(~r/\A\#{1,2}\s+\S/, &1))
          |> Enum.take(4)
          |> Enum.map_join(" | ", fn line ->
            line
            |> String.replace(~r/\A\#{1,2}\s+/, "")
            |> String.trim()
            |> String.slice(0, 64)
          end)
        else
          ""
        end

      _ ->
        ""
    end
  rescue
    _ -> ""
  end

  defp encode_tasks_context(snapshot, user_prompt) do
    lower_prompt = String.downcase(user_prompt)
    count = length(snapshot)
    default_excerpt = if count <= 24, do: 900, else: 280

    {items, _bytes} =
      Enum.reduce(snapshot, {[], 0}, fn row, {acc, used} ->
        mentioned? = task_mentioned?(row, lower_prompt)
        excerpt_limit = if mentioned?, do: 6_000, else: default_excerpt

        item = %{
          "task_id" => Integer.to_string(row.task_id),
          "explicit_id" => row.explicit_id,
          "title" => row.title,
          "state" => row.state,
          "recovery_state" => row.recovery_state,
          "attention_reason" => row.attention_reason,
          "depends_on" => row.depends_on,
          "has_active_workflow" => row.has_active_workflow,
          "has_queued_workflow" => row.has_queued_workflow,
          "spec_excerpt" =>
            if(used < @max_context_bytes,
              do: Cursor.clip_utf8(row.original_text, excerpt_limit),
              else: ""
            )
        }

        encoded = JSON.encode!(item)
        {[item | acc], used + byte_size(encoded)}
      end)

    JSON.encode!(Enum.reverse(items))
  end

  defp task_mentioned?(row, lower_prompt) do
    id_match? =
      Regex.match?(~r/(?:^|\D)#{row.task_id}(?:\D|$)/, lower_prompt)

    explicit_match? =
      is_binary(row.explicit_id) and
        String.contains?(lower_prompt, String.downcase(row.explicit_id))

    id_match? or explicit_match?
  end

  # --- Strict JSON Decoding ---

  defp decode_object(text) do
    case Jason.decode(text, objects: :ordered_objects) do
      {:ok, %Jason.OrderedObject{values: pairs}} ->
        keys = Enum.map(pairs, &elem(&1, 0))
        map = Map.new(pairs)

        cond do
          Enum.uniq(keys) != keys ->
            {:error, :duplicate_keys}

          keys -- @top_keys != [] ->
            {:error, :unknown_fields}

          Enum.sort(keys) != @top_keys ->
            {:error, :invalid_shape}

          not valid_multiline?(map["summary"], 1_200) ->
            {:error, :invalid_summary}

          not is_list(map["actions"]) ->
            {:error, :invalid_shape}

          length(map["actions"]) > @max_actions ->
            {:error, :action_limit}

          true ->
            with {:ok, actions} <- decode_actions(map["actions"]) do
              {:ok, %{"summary" => String.trim(map["summary"]), "actions" => actions}}
            end
        end

      {:ok, _} ->
        {:error, :invalid_shape}

      {:error, _} ->
        {:error, :invalid_json}
    end
  end

  defp decode_actions(items) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case decode_action(item) do
        {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp decode_action(%Jason.OrderedObject{values: pairs}) do
    keys = Enum.map(pairs, &elem(&1, 0))

    cond do
      Enum.uniq(keys) != keys ->
        {:error, :duplicate_keys}

      keys -- @action_keys != [] ->
        {:error, :unknown_fields}

      true ->
        raw =
          Map.new(@action_keys, &{&1, nil})
          |> Map.merge(Map.new(pairs))

        validate_action_fields(raw)
    end
  end

  defp decode_action(_), do: {:error, :invalid_shape}

  defp validate_action_fields(%{"op" => op} = raw) when op in @ops do
    case op do
      "create_task" ->
        with true <- valid_slug?(raw["task_ref"]) || {:error, :invalid_task_id},
             true <- valid_single_line?(raw["title"], 200) || {:error, :invalid_title},
             true <-
               valid_multiline?(raw["specification"], 8_000) ||
                 {:error, :invalid_specification},
             {:ok, acceptance} <- validate_acceptance(raw["acceptance"]),
             {:ok, depends_on} <- validate_depends_list(raw["depends_on"]),
             true <- is_nil(raw["reason"]) || {:error, :invalid_reason} do
          {:ok,
           %{
             "op" => op,
             "task_ref" => raw["task_ref"],
             "title" => String.trim(raw["title"]),
             "specification" => String.trim(raw["specification"]),
             "acceptance" => acceptance,
             "depends_on" => depends_on,
             "reason" => nil
           }}
        end

      "update_task_spec" ->
        with true <- valid_ref?(raw["task_ref"]) || {:error, :invalid_task_ref},
             true <- valid_single_line?(raw["title"], 200) || {:error, :invalid_title},
             true <-
               valid_multiline?(raw["specification"], 8_000) ||
                 {:error, :invalid_specification},
             {:ok, acceptance} <- validate_acceptance(raw["acceptance"]),
             {:ok, depends_on} <- validate_depends_list(raw["depends_on"]),
             true <- is_nil(raw["reason"]) || {:error, :invalid_reason} do
          {:ok,
           %{
             "op" => op,
             "task_ref" => String.trim(raw["task_ref"]),
             "title" => String.trim(raw["title"]),
             "specification" => String.trim(raw["specification"]),
             "acceptance" => acceptance,
             "depends_on" => depends_on,
             "reason" => nil
           }}
        end

      op when op in ~w(add_task_note block_task needs_input_task cancel_task) ->
        with true <- valid_ref?(raw["task_ref"]) || {:error, :invalid_task_ref},
             true <- valid_multiline?(raw["reason"], 1_000) || {:error, :invalid_reason},
             true <- spec_fields_nil?(raw) || {:error, :invalid_shape} do
          {:ok,
           %{
             "op" => op,
             "task_ref" => String.trim(raw["task_ref"]),
             "title" => nil,
             "specification" => nil,
             "acceptance" => nil,
             "depends_on" => nil,
             "reason" => String.trim(raw["reason"])
           }}
        end

      op
      when op in ~w(resume_task retry_task start_workflow queue_workflow cancel_queued_workflow stop_workflow) ->
        with true <- valid_ref?(raw["task_ref"]) || {:error, :invalid_task_ref},
             true <- is_nil(raw["reason"]) || {:error, :invalid_reason},
             true <- spec_fields_nil?(raw) || {:error, :invalid_shape} do
          {:ok,
           %{
             "op" => op,
             "task_ref" => String.trim(raw["task_ref"]),
             "title" => nil,
             "specification" => nil,
             "acceptance" => nil,
             "depends_on" => nil,
             "reason" => nil
           }}
        end
    end
  end

  defp validate_action_fields(_), do: {:error, :invalid_op}

  defp spec_fields_nil?(raw) do
    is_nil(raw["title"]) and is_nil(raw["specification"]) and
      is_nil(raw["acceptance"]) and is_nil(raw["depends_on"])
  end

  defp validate_acceptance(items) when is_list(items) and length(items) in 1..12 do
    if Enum.all?(items, &valid_single_line?(&1, 500)) do
      cleaned = Enum.map(items, &String.trim/1)

      if Enum.uniq(cleaned) == cleaned,
        do: {:ok, cleaned},
        else: {:error, :invalid_acceptance}
    else
      {:error, :invalid_acceptance}
    end
  end

  defp validate_acceptance(_), do: {:error, :invalid_acceptance}

  defp validate_depends_list(nil), do: {:ok, []}

  defp validate_depends_list(items) when is_list(items) and length(items) <= 32 do
    if Enum.all?(items, &valid_ref?/1) do
      cleaned = Enum.map(items, &String.trim/1)

      if Enum.uniq(cleaned) == cleaned,
        do: {:ok, cleaned},
        else: {:error, :invalid_dependencies}
    else
      {:error, :invalid_dependencies}
    end
  end

  defp validate_depends_list(_), do: {:error, :invalid_dependencies}

  # --- Action Application ---

  defp apply_action(project, %{"op" => "create_task"} = action, refs, opts) do
    id = action["task_ref"]

    with :ok <- ensure_unused_id(project.id, id, refs),
         {:ok, deps} <- resolve_depends_on(action["depends_on"], id, refs),
         text =
           format_spec_markdown(
             id,
             action["title"],
             action["specification"],
             action["acceptance"],
             deps
           ),
         {:ok, saved} <- persist_new_spec(project, id, action["title"], text) do
      log_analytic_entry(
        project.id,
        saved.task.id,
        opts,
        "spec_update",
        "Created task #{id}",
        action["specification"]
      )

      next_refs =
        refs
        |> Map.put(id, %{task_id: saved.task.id, explicit_id: id, title: saved.task.title})
        |> Map.put(Integer.to_string(saved.task.id), %{
          task_id: saved.task.id,
          explicit_id: id,
          title: saved.task.title
        })

      {result_entry(
         "create_task",
         :applied,
         saved.task.id,
         saved.task.title,
         "Created Backlog task #{id}."
       ), next_refs, true}
    else
      {:error, detail} ->
        {result_entry("create_task", :failed, nil, action["title"] || id, detail), refs, false}
    end
  end

  defp apply_action(project, %{"op" => "update_task_spec"} = action, refs, opts) do
    with {:ok, target} <- resolve_target_task(project.id, action["task_ref"], refs),
         true <-
           not Documentation.reference_only?(target.task.id) ||
             {:error, "Reference-only tasks cannot be modified."},
         explicit_id = extract_explicit_id(target.spec.identity_key),
         {:ok, deps} <- resolve_depends_on(action["depends_on"], explicit_id, refs),
         text =
           format_spec_markdown(
             explicit_id,
             action["title"],
             action["specification"],
             action["acceptance"],
             deps
           ),
         {:ok, outcome} <-
           persist_updated_spec(project, target, action["title"], explicit_id, text) do
      log_analytic_entry(
        project.id,
        outcome.task_id,
        opts,
        "spec_update",
        "Updated specification: #{outcome.title}",
        action["specification"]
      )

      {result_entry("update_task_spec", :applied, outcome.task_id, outcome.title, outcome.detail),
       refs, true}
    else
      {:error, detail} ->
        {result_entry("update_task_spec", :failed, nil, action["task_ref"], detail), refs, false}
    end
  end

  defp apply_action(project, %{"op" => "add_task_note"} = action, refs, opts) do
    with {:ok, target} <- resolve_target_task(project.id, action["task_ref"], refs),
         {:ok, _} <-
           Boss.Tasks.Entries.add_comment(project.id, target.task.id, %{
             author_role: "analytic",
             agent_id: Map.get(opts, :agent),
             model_id: Map.get(opts, :model_id),
             kind: "comment",
             stage: "prompt",
             body: action["reason"]
           }) do
      {result_entry(
         "add_task_note",
         :applied,
         target.task.id,
         target.task.title,
         "Added Analytic note to task."
       ), refs, true}
    else
      {:error, reason} ->
        {target_id, title} = fallback_target_label(project.id, action["task_ref"], refs)

        {result_entry(
           "add_task_note",
           :failed,
           target_id,
           title,
           transition_error_detail(reason)
         ), refs, false}
    end
  end

  defp apply_action(project, %{"op" => op} = action, refs, opts)
       when op in ~w(block_task needs_input_task cancel_task) do
    transition_action =
      case op do
        "block_task" -> "block"
        "needs_input_task" -> "needs_input"
        "cancel_task" -> "cancel"
      end

    with {:ok, target} <- resolve_target_task(project.id, action["task_ref"], refs),
         :ok <- ensure_not_actively_running(target.task.id),
         :ok <- maybe_cancel_queued_for_task_cancel(project.id, target.task.id, transition_action),
         fresh = Repo.get!(Task, target.task.id),
         {:ok, _event} <-
           Tasks.transition(fresh.id, %{
             action: transition_action,
             expected_version: fresh.state_version,
             command_id: Ecto.UUID.generate(),
             reason: action["reason"]
           }) do
      updated = Repo.get!(Task, fresh.id)

      log_analytic_entry(
        project.id,
        updated.id,
        opts,
        "comment",
        "Moved task to #{state_name(updated.state)}",
        action["reason"] || ""
      )

      {result_entry(
         op,
         :applied,
         updated.id,
         updated.title,
         "Task moved to #{state_name(updated.state)}."
       ), refs, true}
    else
      {:error, reason} ->
        {target_id, title} = fallback_target_label(project.id, action["task_ref"], refs)

        {result_entry(op, :failed, target_id, title, transition_error_detail(reason)), refs,
         false}
    end
  end

  defp apply_action(project, %{"op" => op} = action, refs, _opts)
       when op in ~w(resume_task retry_task) do
    transition_action = if op == "resume_task", do: "resume", else: "retry"

    with {:ok, target} <- resolve_target_task(project.id, action["task_ref"], refs),
         {:ok, detail} <- resume_or_retry(project.id, target.task, transition_action) do
      updated = Repo.get!(Task, target.task.id)
      {result_entry(op, :applied, updated.id, updated.title, detail), refs, true}
    else
      {:error, reason} ->
        {target_id, title} = fallback_target_label(project.id, action["task_ref"], refs)

        {result_entry(op, :failed, target_id, title, transition_error_detail(reason)), refs,
         false}
    end
  end

  defp apply_action(project, %{"op" => op} = action, refs, opts)
       when op in ~w(start_workflow queue_workflow) do
    check_text = String.trim(Map.get(opts, :check_command, "") || "")

    reviewer =
      Map.get(opts, :reviewer) || Boss.Projects.RoleBindings.reviewer_agent(project.id)

    server = Map.get(opts, :server, Boss.Runs.Manager)

    with {:ok, target} <- resolve_target_task(project.id, action["task_ref"], refs),
         true <-
           match?({:ok, _, _}, Boss.Checks.Command.parse_workflow(check_text)) ||
             {:error, "Check command could not be parsed."},
         true <-
           Metadata.review_runner?(reviewer) ||
             {:error, "Choose a valid independent reviewer before starting or queueing."},
         {:ok, detail} <-
           dispatch_workflow(op, project.id, target.task.id, check_text, reviewer, server) do
      updated = Repo.get!(Task, target.task.id)
      log_analytic_entry(project.id, updated.id, opts, "stage_log", detail, "")
      {result_entry(op, :applied, updated.id, updated.title, detail), refs, true}
    else
      {:error, reason} ->
        {target_id, title} = fallback_target_label(project.id, action["task_ref"], refs)
        {result_entry(op, :failed, target_id, title, workflow_error_detail(reason)), refs, false}
    end
  end

  defp apply_action(project, %{"op" => "cancel_queued_workflow"} = action, refs, _opts) do
    with {:ok, target} <- resolve_target_task(project.id, action["task_ref"], refs),
         request when not is_nil(request) <-
           find_queued_request(target.task.id) ||
             {:error, "No queued or paused workflow request exists for this task."},
         {:ok, _} <- Queue.cancel(project.id, request.id) do
      {result_entry(
         "cancel_queued_workflow",
         :applied,
         target.task.id,
         target.task.title,
         "Cancelled queued workflow request."
       ), refs, true}
    else
      {:error, reason} ->
        {target_id, title} = fallback_target_label(project.id, action["task_ref"], refs)

        {result_entry(
           "cancel_queued_workflow",
           :failed,
           target_id,
           title,
           workflow_error_detail(reason)
         ), refs, false}
    end
  end

  defp apply_action(project, %{"op" => "stop_workflow"} = action, refs, _opts) do
    with {:ok, target} <- resolve_target_task(project.id, action["task_ref"], refs),
         {:ok, detail} <- stop_active_work(project.id, target.task.id) do
      {result_entry("stop_workflow", :applied, target.task.id, target.task.title, detail), refs,
       true}
    else
      {:error, reason} ->
        {target_id, title} = fallback_target_label(project.id, action["task_ref"], refs)

        {result_entry("stop_workflow", :failed, target_id, title, workflow_error_detail(reason)),
         refs, false}
    end
  end

  # --- Helpers for Persisting & Controlling Tasks ---

  defp log_analytic_entry(project_id, task_id, opts, kind, summary, body) do
    _ =
      Boss.Tasks.Entries.add_comment(project_id, task_id, %{
        author_role: "analytic",
        agent_id: Map.get(opts, :agent),
        model_id: Map.get(opts, :model_id),
        kind: kind,
        stage: "prompt",
        summary: summary,
        body: body || summary
      })

    :ok
  end

  defp persist_new_spec(project, id, title, text) do
    relative_path = "prompts/#{id}.md"

    attrs = %{
      relative_path: relative_path,
      explicit_id: id,
      title: title,
      original_text: text
    }

    if project.intake_mode == "specs" do
      with {:ok, file_path} <- write_new_spec_file(project, relative_path, text) do
        case Projects.record_spec(project.id, attrs) do
          {:ok, %{change: :created} = saved} ->
            {:ok, saved}

          {:ok, _} ->
            _ = File.rm(file_path)
            {:error, "Task #{id} already exists."}

          {:error, _} ->
            _ = File.rm(file_path)
            {:error, "Could not save specification for #{id}."}
        end
      end
    else
      case Projects.record_spec(project.id, attrs) do
        {:ok, %{change: :created} = saved} -> {:ok, saved}
        {:ok, _} -> {:error, "Task #{id} already exists."}
        {:error, _} -> {:error, "Could not save specification for #{id}."}
      end
    end
  end

  defp persist_updated_spec(project, %{task: task, spec: spec}, title, explicit_id, text) do
    attrs =
      %{
        relative_path: spec.relative_path,
        title: title,
        original_text: text
      }
      |> then(fn base ->
        if is_binary(explicit_id), do: Map.put(base, :explicit_id, explicit_id), else: base
      end)

    with :ok <- maybe_write_updated_spec_file(project, spec, text),
         {:ok, %{revision: revision, change: change}} <-
           Projects.record_spec(project.id, attrs) |> map_record_error() do
      fresh_task = Repo.get!(Task, task.id)
      pinned = Repo.get!(SpecRevision, fresh_task.spec_revision_id)

      cond do
        change == :unchanged and fresh_task.spec_revision_id == revision.id ->
          {:ok,
           %{
             task_id: fresh_task.id,
             title: fresh_task.title,
             detail: "Specification is already up to date at revision #{revision.number}."
           }}

        Revisions.status(fresh_task, spec, pinned, revision).available? ->
          case Tasks.transition(fresh_task.id, %{
                 action: "adopt_revision",
                 project_id: project.id,
                 spec_revision_id: revision.id,
                 expected_version: fresh_task.state_version,
                 command_id: Ecto.UUID.generate()
               }) do
            {:ok, _} ->
              adopted = Repo.get!(Task, fresh_task.id)

              {:ok,
               %{
                 task_id: adopted.id,
                 title: adopted.title,
                 detail: "Saved and adopted revision #{revision.number}."
               }}

            _ ->
              {:ok,
               %{
                 task_id: fresh_task.id,
                 title: fresh_task.title,
                 detail:
                   "Saved revision #{revision.number}; adopt it from the task drawer when idle."
               }}
          end

        true ->
          {:ok,
           %{
             task_id: fresh_task.id,
             title: fresh_task.title,
             detail:
               "Saved revision #{revision.number}; task kept snapshot #{pinned.number} while busy or completed."
           }}
      end
    end
  end

  defp map_record_error({:ok, _} = ok), do: ok
  defp map_record_error({:error, _}), do: {:error, "Updated specification could not be saved."}

  defp write_new_spec_file(project, "prompts/" <> filename, text) do
    with {:ok, specs_root} <- Repository.specs_directory(project.root_path, project.specs_path),
         {:ok, prompts_dir} <- ensure_real_subdir(specs_root, "prompts") do
      target = Path.join(prompts_dir, filename)

      case File.open(target, [:write, :raw, :exclusive]) do
        {:ok, io} ->
          try do
            case :file.write(io, text) do
              :ok -> {:ok, target}
              {:error, _} -> {:error, "Could not write spec file."}
            end
          after
            File.close(io)
          end

        {:error, :eexist} ->
          {:error, "Spec file prompts/#{filename} already exists."}

        {:error, _} ->
          {:error, "Could not create spec file in specs directory."}
      end
    else
      _ -> {:error, "Specs directory is unavailable or contains symlinks."}
    end
  end

  defp maybe_write_updated_spec_file(
         %{intake_mode: "specs"} = project,
         %{missing: false} = spec,
         text
       ) do
    with {:ok, specs_root} <- Repository.specs_directory(project.root_path, project.specs_path),
         {:ok, file_path} <- verify_existing_spec_file(specs_root, spec.relative_path) do
      case File.write(file_path, text) do
        :ok -> :ok
        {:error, _} -> {:error, "Could not update spec file on disk."}
      end
    else
      _ -> {:error, "Existing spec file is unavailable or contains symlinks."}
    end
  end

  defp maybe_write_updated_spec_file(_, _, _), do: :ok

  defp ensure_real_subdir(parent, name) do
    dir = Path.join(parent, name)

    case :file.make_dir(dir) do
      :ok ->
        {:ok, dir}

      {:error, :eexist} ->
        case File.lstat(dir) do
          {:ok, %{type: :directory}} -> {:ok, dir}
          _ -> {:error, :invalid_directory}
        end

      {:error, _} ->
        {:error, :mkdir_failed}
    end
  end

  defp verify_existing_spec_file(specs_root, relative_path) do
    parts = String.split(relative_path, "/")
    {dirs, [file]} = Enum.split(parts, length(parts) - 1)

    with {:ok, dir_path} <-
           Enum.reduce_while(dirs, {:ok, specs_root}, fn segment, {:ok, acc} ->
             next = Path.join(acc, segment)

             case File.lstat(next) do
               {:ok, %{type: :directory}} -> {:cont, {:ok, next}}
               _ -> {:halt, {:error, :invalid_path}}
             end
           end) do
      full = Path.join(dir_path, file)

      case File.lstat(full) do
        {:ok, %{type: :regular}} -> {:ok, full}
        _ -> {:error, :invalid_file}
      end
    end
  end

  defp format_spec_markdown(explicit_id, title, specification, acceptance, depends_on) do
    id_line = if is_binary(explicit_id), do: "id: #{JSON.encode!(explicit_id)}\n", else: ""
    deps_line = "depends_on: #{JSON.encode!(depends_on)}"
    criteria = Enum.map_join(acceptance, "\n", &("- " <> &1))

    """
    ---
    #{id_line}#{deps_line}
    ---
    # #{title}

    #{specification}

    ## Acceptance criteria
    #{criteria}
    """
  end

  defp ensure_unused_id(project_id, id, refs) do
    identity = "id:" <> id
    rel_path = "prompts/#{id}.md"

    cond do
      Map.has_key?(refs, id) ->
        {:error, "Task ID #{id} is already in use in this project."}

      Repo.exists?(
        from s in Spec,
          where:
            s.project_id == ^project_id and
                (s.identity_key == ^identity or s.relative_path == ^rel_path)
      ) ->
        {:error, "Task ID #{id} already exists in this project."}

      true ->
        :ok
    end
  end

  defp resolve_depends_on(deps, self_id, refs) do
    Enum.reduce_while(deps, {:ok, []}, fn raw_dep, {:ok, acc} ->
      dep = String.trim(raw_dep) |> String.trim_leading("#")

      cond do
        is_binary(self_id) and dep == self_id ->
          {:halt, {:error, "Task #{self_id} cannot depend on itself."}}

        entry = Map.get(refs, dep) ->
          if is_binary(entry.explicit_id) do
            if entry.explicit_id == self_id do
              {:halt, {:error, "Task #{self_id} cannot depend on itself."}}
            else
              {:cont, {:ok, [entry.explicit_id | acc]}}
            end
          else
            {:halt,
             {:error,
              "Dependency #{raw_dep} does not declare an explicit frontmatter id and cannot be referenced in depends_on."}}
          end

        valid_slug?(dep) ->
          {:halt, {:error, "Dependency #{dep} does not match any task in this project."}}

        true ->
          {:halt, {:error, "Invalid dependency reference #{raw_dep}."}}
      end
    end)
    |> case do
      {:ok, resolved} -> {:ok, Enum.reverse(Enum.uniq(resolved))}
      error -> error
    end
  end

  defp resolve_target_task(project_id, raw_ref, refs) do
    cleaned = String.trim(raw_ref) |> String.trim_leading("#")

    task_id =
      cond do
        entry = Map.get(refs, cleaned) ->
          entry.task_id

        match?({_num, ""}, Integer.parse(cleaned)) ->
          {num, ""} = Integer.parse(cleaned)
          num

        true ->
          nil
      end

    with id when is_integer(id) and id > 0 <-
           task_id || {:error, "Task #{raw_ref} was not found."},
         {task, spec} when not is_nil(task) <-
           Repo.one(
             from t in Task,
               join: s in Spec,
               on: s.id == t.spec_id,
               where: t.id == ^id and s.project_id == ^project_id,
               select: {t, s}
           ) || {:error, "Task #{raw_ref} was not found in this project."} do
      {:ok, %{task: task, spec: spec}}
    end
  end

  defp fallback_target_label(project_id, raw_ref, refs) do
    case resolve_target_task(project_id, raw_ref, refs) do
      {:ok, %{task: task}} -> {task.id, task.title}
      _ -> {nil, raw_ref}
    end
  end

  defp ensure_not_actively_running(task_id) do
    active_delivery? =
      Repo.exists?(
        from d in Delivery,
          where:
            d.task_id == ^task_id and
              (d.status in ^@active_delivery_statuses or d.cleanup == "unknown")
      )

    active_run? =
      Repo.exists?(
        from r in Runs.Run,
          where:
            r.task_id == ^task_id and
              (r.status in ^@active_run_statuses or r.cleanup == "unknown")
      )

    if active_delivery? or active_run? do
      {:error, "Task has an active or unconfirmed execution; stop the workflow first."}
    else
      :ok
    end
  end

  defp maybe_cancel_queued_for_task_cancel(project_id, task_id, "cancel") do
    case find_queued_request(task_id) do
      nil ->
        :ok

      request ->
        case Queue.cancel(project_id, request.id) do
          {:ok, _} -> :ok
          _ -> {:error, "Could not cancel the task's pending queued workflow."}
        end
    end
  end

  defp maybe_cancel_queued_for_task_cancel(_, _, _), do: :ok

  defp resume_or_retry(project_id, task, "resume") do
    case Repo.one(
           from r in Request,
             where: r.task_id == ^task.id and r.status == "paused",
             order_by: [desc: r.inserted_at],
             limit: 1
         ) do
      %Request{} = paused ->
        case Queue.resume(project_id, paused.id) do
          {:ok, _} -> {:ok, "Resumed paused workflow request in queue."}
          {:error, reason} -> {:error, reason}
        end

      nil ->
        case Tasks.transition(task.id, %{
               action: "resume",
               expected_version: task.state_version,
               command_id: Ecto.UUID.generate()
             }) do
          {:ok, _} -> {:ok, "Resumed task to Backlog."}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp resume_or_retry(_project_id, task, "retry") do
    case Tasks.transition(task.id, %{
           action: "retry",
           expected_version: task.state_version,
           command_id: Ecto.UUID.generate()
         }) do
      {:ok, _} -> {:ok, "Reset task to Backlog."}
      {:error, reason} -> {:error, reason}
    end
  end

  defp dispatch_workflow("start_workflow", project_id, task_id, check_text, reviewer, server) do
    case Deliveries.start(project_id, task_id, Ecto.UUID.generate(), check_text, reviewer, server) do
      {:ok, _delivery} -> {:ok, "Started managed workflow."}
      {:error, reason} -> {:error, reason}
    end
  end

  defp dispatch_workflow("queue_workflow", project_id, task_id, check_text, reviewer, server) do
    case Queue.enqueue(project_id, task_id, Ecto.UUID.generate(), check_text, reviewer, server) do
      {:ok, _request} -> {:ok, "Queued managed workflow."}
      {:error, reason} -> {:error, reason}
    end
  end

  defp find_queued_request(task_id) do
    Repo.one(
      from r in Request,
        where: r.task_id == ^task_id and r.status in ~w(queued paused),
        order_by: [desc: r.inserted_at],
        limit: 1
    )
  end

  defp stop_active_work(project_id, task_id) do
    active_delivery =
      Repo.one(
        from d in Delivery,
          where: d.task_id == ^task_id and d.status in ^@active_delivery_statuses,
          order_by: [desc: d.inserted_at],
          limit: 1
      )

    active_run =
      Repo.one(
        from r in Runs.Run,
          where: r.task_id == ^task_id and r.status in ^@active_run_statuses,
          order_by: [desc: r.inserted_at],
          limit: 1
      )

    cond do
      active_delivery != nil ->
        case Deliveries.stop(project_id, active_delivery.id) do
          :ok -> {:ok, "Requested Stop on active workflow."}
          {:error, reason} -> {:error, reason}
        end

      active_run != nil ->
        case Runs.stop(project_id, active_run.id) do
          :ok -> {:ok, "Requested Stop on active manual run."}
          {:error, reason} -> {:error, reason}
        end

      true ->
        {:error, "No active workflow or run is executing on this task."}
    end
  end

  # --- Snapshot & Reference Queries ---

  defp load_tasks_snapshot(project_id) do
    rows =
      Repo.all(
        from t in Task,
          join: s in Spec,
          on: s.id == t.spec_id,
          join: r in SpecRevision,
          on: r.id == t.spec_revision_id and r.spec_id == s.id,
          where:
            s.project_id == ^project_id and not s.missing and
              fragment(
                "NOT EXISTS (SELECT 1 FROM project_documentation_sources refs WHERE refs.task_id=?)",
                t.id
              ),
          order_by: t.id,
          limit: 256,
          select: %{
            task_id: t.id,
            title: t.title,
            state: t.state,
            recovery_state: t.recovery_state,
            attention_reason: t.attention_reason,
            identity_key: s.identity_key,
            relative_path: s.relative_path,
            original_text: r.original_text,
            has_active_workflow:
              type(
                fragment(
                  "EXISTS (SELECT 1 FROM deliveries d WHERE d.task_id=? AND d.status IN ('planning','implementing','testing','reviewing','integrating'))",
                  t.id
                ),
                :boolean
              ),
            has_queued_workflow:
              type(
                fragment(
                  "EXISTS (SELECT 1 FROM delivery_requests q WHERE q.task_id=? AND q.status IN ('queued','paused'))",
                  t.id
                ),
                :boolean
              )
          }
      )

    Enum.map(rows, fn row ->
      deps =
        case SpecDocument.dependencies(row.original_text) do
          {:ok, list} when is_list(list) -> list
          _ -> []
        end

      row
      |> Map.put(:explicit_id, extract_explicit_id(row.identity_key))
      |> Map.put(:depends_on, deps)
    end)
  end

  defp build_ref_map(snapshot) do
    Enum.reduce(snapshot, %{}, fn row, acc ->
      entry = %{task_id: row.task_id, explicit_id: row.explicit_id, title: row.title}
      acc = Map.put(acc, Integer.to_string(row.task_id), entry)
      if is_binary(row.explicit_id), do: Map.put(acc, row.explicit_id, entry), else: acc
    end)
  end

  defp extract_explicit_id("id:" <> id), do: id
  defp extract_explicit_id(_), do: nil

  # --- Validation & Error Formatting ---

  defp validate_request(project_id, request_id, params) do
    prompt = Map.get(params, :prompt)
    agent = Map.get(params, :agent)
    reviewer = Map.get(params, :reviewer, "codex")
    check_cmd = Map.get(params, :check_command, "")

    cond do
      not (is_integer(project_id) and project_id > 0) ->
        {:error, :project_not_found}

      not match?({:ok, ^request_id}, Ecto.UUID.cast(request_id)) ->
        {:error, :invalid_prompt}

      not valid_multiline?(prompt, @max_prompt_bytes) ->
        {:error, :invalid_prompt}

      not Metadata.execution_runner?(agent) ->
        {:error, :invalid_agent}

      not Metadata.review_runner?(reviewer) ->
        {:error, :invalid_reviewer}

      not (is_binary(check_cmd) and byte_size(check_cmd) <= @max_check_bytes and
             String.valid?(check_cmd) and not String.contains?(check_cmd, <<0>>)) ->
        {:error, :invalid_check_command}

      true ->
        :ok
    end
  end

  defp fetch_project(project_id) do
    case Repo.get(Project, project_id) do
      %Project{} = project -> {:ok, project}
      nil -> {:error, :project_not_found}
    end
  end

  defp validate_root_directory(path) when is_binary(path) do
    case File.stat(path) do
      {:ok, %{type: :directory}} -> :ok
      _ -> {:error, :invalid_repository}
    end
  end

  defp validate_root_directory(_), do: {:error, :invalid_repository}

  defp valid_slug?(value) when is_binary(value) do
    byte_size(value) in 1..64 and String.valid?(value) and
      Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, value)
  end

  defp valid_slug?(_), do: false

  defp valid_ref?(value) when is_binary(value) do
    trimmed = String.trim(value)

    byte_size(trimmed) in 1..200 and String.valid?(trimmed) and
      not String.contains?(trimmed, [<<0>>, "\n", "\r"])
  end

  defp valid_ref?(_), do: false

  defp valid_single_line?(value, max_bytes, max_chars \\ nil)

  defp valid_single_line?(value, max_bytes, max_chars) when is_binary(value) do
    trimmed = String.trim(value)
    char_limit = max_chars || max_bytes

    trimmed != "" and byte_size(trimmed) <= max_bytes and String.length(trimmed) <= char_limit and
      String.valid?(trimmed) and not String.contains?(trimmed, [<<0>>, "\n", "\r"])
  end

  defp valid_single_line?(_, _, _), do: false

  defp valid_multiline?(value, max_bytes) when is_binary(value) do
    trimmed = String.trim(value)

    trimmed != "" and byte_size(trimmed) <= max_bytes and String.valid?(trimmed) and
      not String.contains?(trimmed, <<0>>)
  end

  defp valid_multiline?(_, _), do: false

  defp sanitize_single_line(text, max_bytes) when is_binary(text) do
    text
    |> String.replace(~r/[\p{Cc}]+/u, " ")
    |> String.trim()
    |> Cursor.clip_utf8(max_bytes)
  end

  defp sanitize_multiline(text, max_bytes) when is_binary(text) do
    text
    |> String.replace(~r/[^\P{Cc}\n\t]+/u, "")
    |> String.trim()
    |> Cursor.clip_utf8(max_bytes)
  end

  defp result_entry(op, status, task_id, title, detail) do
    %{
      op: op,
      status: status,
      task_id: task_id,
      title: sanitize_single_line(to_string(title || ""), 200),
      detail: sanitize_single_line(to_string(detail || ""), 320)
    }
  end

  defp state_name("new"), do: "Backlog"
  defp state_name("needs_input"), do: "Needs Input"
  defp state_name("blocked"), do: "Blocked"
  defp state_name("cancelled"), do: "Cancelled"
  defp state_name("failed"), do: "Failed"
  defp state_name("interrupted"), do: "Interrupted"
  defp state_name(other), do: other

  defp transition_error_detail(reason) when is_binary(reason), do: reason

  defp transition_error_detail({:gate_unavailable, _}),
    do: "This task halted during an execution stage; start or queue a workflow to retry it."

  defp transition_error_detail(:reference_only),
    do: "Reference-only tasks cannot be modified."

  defp transition_error_detail(:invalid_transition),
    do: "That state transition is not valid from the task's current state."

  defp transition_error_detail(:stale_state),
    do: "The task changed concurrently; try again."

  defp transition_error_detail(_),
    do: "Task transition could not be applied."

  defp workflow_error_detail(reason) when is_binary(reason), do: reason

  defp workflow_error_detail(:busy),
    do: "Workflow capacity is full, an exclusive run is active, or cleanup needs attention."

  defp workflow_error_detail(:task_queued),
    do: "This task already has a queued workflow."

  defp workflow_error_detail(:queue_full),
    do: "The workflow queue is full."

  defp workflow_error_detail({:dependencies_blocked, _}),
    do: "Task dependencies are not Done yet; use Queue workflow instead of Start."

  defp workflow_error_detail(:reference_only),
    do: "Reference-only tasks cannot execute workflows."

  defp workflow_error_detail(:task_unavailable),
    do: "This task cannot start a workflow from its current state."

  defp workflow_error_detail(:invalid_check_command),
    do: "Enter a valid Check command in Workflow settings."

  defp workflow_error_detail(_),
    do: "Workflow action could not be completed."

  # --- Active ETS Registry ---

  defp claim_active(project_id, request_id) do
    table = active_table()
    me = self()

    case :ets.lookup(table, project_id) do
      [{^project_id, existing_id, pid}] when is_pid(pid) ->
        if Process.alive?(pid) do
          {:error, :busy}
        else
          :ets.delete_object(table, {project_id, existing_id, pid})
          if :ets.insert_new(table, {project_id, request_id, me}), do: :ok, else: {:error, :busy}
        end

      [] ->
        if :ets.insert_new(table, {project_id, request_id, me}), do: :ok, else: {:error, :busy}
    end
  end

  defp release_active(project_id, request_id) do
    :ets.delete_object(active_table(), {project_id, request_id, self()})
    :ok
  end

  defp active_table do
    case :ets.whereis(:boss_task_prompts) do
      :undefined ->
        try do
          :ets.new(:boss_task_prompts, [
            :named_table,
            :public,
            :set,
            {:read_concurrency, true},
            {:heir, Process.whereis(:init), :none}
          ])
        rescue
          ArgumentError -> :boss_task_prompts
        end

      _ ->
        :boss_task_prompts
    end
  end
end
