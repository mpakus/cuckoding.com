defmodule Cuckoding.Knowledge.Injection do
  @moduledoc "Selects reviewed knowledge for a run and records how it is used."

  import Ecto.Query

  alias Cuckoding.Adapters.Types
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Identifier
  alias Cuckoding.Knowledge.Item
  alias Cuckoding.Knowledge.Retrieval
  alias Cuckoding.Knowledge.RetrievalToken
  alias Cuckoding.Knowledge.Store
  alias Cuckoding.Knowledge.Usage
  alias Cuckoding.Projects.Project
  alias Cuckoding.Projects.ProjectConfigVersion
  alias Cuckoding.Repo
  alias Cuckoding.Workflows.Board
  alias Cuckoding.Workflows.Task

  @budget 32_768
  @index_budget 12_000
  @maximum_results 10
  @maximum_query_bytes 4_096
  @token_ttl_seconds 300
  @generic_tokens ~w(and are for from into relevant that the this when with your)

  def prepare(request, options \\ [])

  def prepare(%Types.StageRequest{} = request, options) do
    with {:ok, context} <- context(request.run_id, request.attempt_id),
         :ok <- matching_request(context, request),
         {:ok, items} <- active_items(context, options),
         {:ok, selected} <- select_items(items, context, options),
         {:ok, index} <- Store.read_project_index(context.project),
         entries <- bounded_entries(index, selected) do
      {:ok, %{request | knowledge: entries}}
    end
  end

  def prepare(_request, _options), do: {:error, :invalid_stage_request}

  def record_injection(%Types.StageRequest{} = request) do
    with {:ok, context} <- context(request.run_id, request.attempt_id),
         :ok <- matching_request(context, request),
         {:ok, items} <- injected_items(request.knowledge, context) do
      record_injections(items, context)
    end
  end

  def record_injection(_request), do: {:error, :invalid_stage_request}

  def issue_token(run_id, stage_attempt_id, options \\ [])

  def issue_token(run_id, stage_attempt_id, options)
      when is_binary(run_id) and is_binary(stage_attempt_id) do
    ttl = Keyword.get(options, :ttl_seconds, @token_ttl_seconds)

    with true <- is_integer(ttl) and ttl > 0 and ttl <= 900,
         {:ok, context} <- context(run_id, stage_attempt_id) do
      token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

      attrs = %{
        id: Identifier.generate(),
        run_id: run_id,
        stage_attempt_id: stage_attempt_id,
        project_id: context.project.id,
        token_hash: sha256(token),
        expires_at: DateTime.add(Cuckoding.Clock.wall_now(), ttl, :second)
      }

      case Repo.insert(RetrievalToken.create_changeset(%RetrievalToken{}, attrs)) do
        {:ok, capability} -> {:ok, %{token: token, expires_at: capability.expires_at}}
        {:error, changeset} -> {:error, changeset}
      end
    else
      false -> {:error, :invalid_token_ttl}
      {:error, _reason} = error -> error
    end
  end

  def issue_token(_run_id, _stage_attempt_id, _options), do: {:error, :invalid_run_scope}

  def retrieve(token, query, options \\ [])

  def retrieve(token, query, options)
      when is_binary(token) and is_binary(query) and byte_size(query) <= @maximum_query_bytes do
    query = String.trim(query)

    with true <- query != "",
         {:ok, capability} <- valid_token(token),
         {:ok, context} <- context(capability.run_id, capability.stage_attempt_id),
         true <- context.project.id == capability.project_id,
         {:ok, items} <- active_items(context, options),
         {:ok, documents} <- read_documents(items, context, options),
         selected <- rank(documents, query, options),
         {:ok, retrieval} <- record_retrieval(selected, query, context) do
      {:ok, %{retrieval_id: retrieval.id, results: Enum.map(selected, &result/1)}}
    else
      false -> {:error, :knowledge_capability_scope_refused}
      {:error, _reason} = error -> error
    end
  end

  def retrieve(_token, query, _options) when is_binary(query),
    do: {:error, :invalid_retrieval_query}

  def retrieve(_token, _query, _options), do: {:error, :invalid_retrieval_capability}

  def record_citations(run_id, stage_attempt_id, citations, options \\ []) do
    with {:ok, context} <- context(run_id, stage_attempt_id),
         {:ok, parsed} <- citations(citations) do
      persist_citations(parsed, context, options)
    end
  end

  def record_outcome(run_id, stage_attempt_id, item_id, kind, evidence \\ %{})

  def record_outcome(run_id, stage_attempt_id, item_id, kind, evidence)
      when kind in ~w(accepted contradicted) and is_map(evidence) do
    with {:ok, context} <- context(run_id, stage_attempt_id),
         %Item{} = item <- Repo.get(Item, item_id),
         :ok <- accessible(item, context),
         {:ok, _usage} <-
           insert_usage(
             Repo,
             item,
             context,
             kind,
             evidence,
             "outcome:#{kind}:#{run_id}:#{stage_attempt_id}:#{item.id}:#{item.version}"
           ) do
      :ok
    else
      nil -> {:error, :knowledge_item_not_found}
      {:error, _reason} = error -> error
    end
  end

  def record_outcome(_run_id, _stage_attempt_id, _item_id, _kind, _evidence),
    do: {:error, :invalid_knowledge_outcome}

  def insert_usage(repo, %Item{} = item, context, kind, evidence, event_key)
      when kind in ~w(injected retrieved cited accepted contradicted) and is_map(evidence) do
    hash = sha256(event_key)

    attrs = %{
      id: Identifier.generate(),
      knowledge_item_id: item.id,
      item_version: item.version,
      run_id: context.run.id,
      stage_attempt_id: context.attempt.id,
      kind: kind,
      event_key_hash: hash,
      evidence_json: evidence,
      occurred_at: Cuckoding.Clock.wall_now()
    }

    changeset = Usage.create_changeset(%Usage{}, attrs)

    case repo.insert(changeset, on_conflict: :nothing, conflict_target: :event_key_hash) do
      {:ok, %Usage{id: nil}} -> {:ok, repo.get_by!(Usage, event_key_hash: hash)}
      {:ok, usage} -> {:ok, usage}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def context(run_id, stage_attempt_id) do
    query =
      from(attempt in StageAttempt,
        join: run in Run,
        on: run.id == attempt.run_id,
        join: task in Task,
        on: task.id == run.task_id,
        join: board in Board,
        on: board.id == task.board_id,
        join: project in Project,
        on: project.id == board.project_id,
        join: policy in ProjectConfigVersion,
        on: policy.id == run.policy_snapshot_id,
        where: run.id == ^run_id and attempt.id == ^stage_attempt_id,
        select: %{
          run: run,
          attempt: attempt,
          task: task,
          board: board,
          project: project,
          policy: policy
        }
      )

    case Repo.one(query) do
      nil -> {:error, :knowledge_run_scope_not_found}
      context -> {:ok, context}
    end
  end

  defp matching_request(context, request) do
    matches? =
      {context.project.id, context.board.id, context.task.id, context.run.id,
       context.attempt.stage_key} ==
        {request.project_id, request.board_id, request.task_id, request.run_id, request.stage_key}

    if matches?, do: :ok, else: {:error, :knowledge_request_scope_refused}
  end

  defp active_items(context, options) do
    include_global? = global_enabled?(context.policy)

    items =
      Repo.all(
        from(item in Item,
          where:
            item.sync_state == "synced" and
              ((item.scope == "project" and item.project_id == ^context.project.id and
                  item.status == "project") or
                 (^include_global? and item.scope == "global" and item.status == "global")),
          order_by: [asc: item.scope, asc: item.kind, asc: item.title, asc: item.id]
        )
      )

    superseded = items |> Enum.map(& &1.supersedes_id) |> Enum.reject(&is_nil/1) |> MapSet.new()
    now = Keyword.get(options, :now, Cuckoding.Clock.wall_now())

    {:ok,
     Enum.reject(items, fn item ->
       MapSet.member?(superseded, item.id) or expired?(item, now)
     end)}
  end

  defp select_items(items, context, options) do
    triggers = stage_triggers(context.run.workflow_snapshot_json, context.attempt.stage_key)

    items
    |> Enum.filter(&(kind_triggered?(&1, triggers) or text_triggered?(&1, context)))
    |> read_documents(context, options)
  end

  defp read_documents(items, context, options) do
    read_options =
      if global_enabled?(context.policy),
        do: Keyword.put(options, :include_global, true),
        else: options

    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, documents} ->
      case Store.read_for_project(context.project.id, item.id, read_options) do
        {:ok, document} -> {:cont, {:ok, [document | documents]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, documents} -> {:ok, Enum.reverse(documents)}
      {:error, _reason} = error -> error
    end
  end

  defp bounded_entries(index, selected) do
    entries =
      case index do
        nil ->
          []

        content ->
          [
            %{
              "id" => "project-index",
              "source" => ".cuckoding/knowledge/INDEX.md",
              "trust" => "untrusted",
              "content" => prefix(content, @index_budget)
            }
          ]
      end

    selected
    |> Enum.map(fn %{item: item, document: document} ->
      %{
        "id" => item.id,
        "version" => item.version,
        "scope" => item.scope,
        "trust" => "untrusted",
        "title" => item.title,
        "citation" => "knowledge:#{item.id}@v#{item.version}",
        "content" => document.body
      }
    end)
    |> Enum.reduce(entries, fn entry, accepted ->
      bytes = accepted |> Kernel.++([entry]) |> Enum.sum_by(&byte_size(&1["content"]))
      if bytes <= @budget, do: accepted ++ [entry], else: accepted
    end)
  end

  defp record_injections(selected, context) do
    Repo.transaction(fn ->
      Enum.each(selected, &record_injection!(&1, context))
    end)
    |> case do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp record_injection!(%{item: item}, context) do
    evidence = %{"scope" => item.scope, "stage_key" => context.attempt.stage_key}
    key = "injected:#{context.run.id}:#{context.attempt.id}:#{item.id}:#{item.version}"
    insert_usage(Repo, item, context, "injected", evidence, key) |> unwrap!()
  end

  defp injected_items(entries, context) when is_list(entries) do
    entries
    |> Enum.reject(&(&1["id"] == "project-index"))
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, items} ->
      case injected_item(entry, context) do
        {:ok, item} -> {:cont, {:ok, [item | items]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      {:error, _reason} = error -> error
    end
  end

  defp injected_items(_entries, _context), do: {:error, :invalid_knowledge_injection}

  defp injected_item(entry, context) do
    expected_version = entry["version"]

    case Repo.get(Item, entry["id"]) do
      %Item{version: ^expected_version} = item ->
        with :ok <- injectable(item, context), do: {:ok, %{item: item}}

      %Item{} ->
        {:error, :knowledge_injection_version_mismatch}

      nil ->
        {:error, :knowledge_item_not_found}
    end
  end

  defp valid_token(token) do
    now = Cuckoding.Clock.wall_now()

    case Repo.get_by(RetrievalToken, token_hash: sha256(token)) do
      %RetrievalToken{expires_at: expires_at} = capability ->
        if DateTime.after?(expires_at, now),
          do: {:ok, capability},
          else: {:error, :knowledge_capability_expired}

      nil ->
        {:error, :knowledge_capability_invalid}
    end
  end

  defp rank(documents, query, options) do
    limit = options |> Keyword.get(:limit, 5) |> result_limit()
    query_tokens = tokens(query)

    documents
    |> Enum.map(&Map.put(&1, :score, score(&1, query_tokens)))
    |> Enum.filter(&(&1.score > 0))
    |> Enum.sort_by(&{-&1.score, &1.item.title, &1.item.id})
    |> Enum.take(limit)
    |> bounded_results()
  end

  defp bounded_results(documents) do
    Enum.reduce(documents, [], fn document, accepted ->
      bytes = accepted |> Kernel.++([document]) |> Enum.sum_by(&byte_size(&1.document.body))
      if bytes <= @budget, do: accepted ++ [document], else: accepted
    end)
  end

  defp score(%{item: item, document: parsed}, query_tokens) do
    title = tokens(item.title)
    body = tokens(parsed.body)
    triggers = tokens(Enum.join(item.triggers_json, " "))

    5 * overlap(query_tokens, title) + 2 * overlap(query_tokens, triggers) +
      overlap(query_tokens, body)
  end

  defp record_retrieval(selected, query, context) do
    attrs = %{
      id: Identifier.generate(),
      run_id: context.run.id,
      stage_attempt_id: context.attempt.id,
      backend_key: "file_index",
      namespace: namespace(context),
      query_hash: sha256(query),
      hit_count: length(selected),
      context_bytes: Enum.sum_by(selected, &byte_size(&1.document.body)),
      selected_ids_json: %{"ids" => Enum.map(selected, & &1.item.id)},
      occurred_at: Cuckoding.Clock.wall_now()
    }

    Repo.transaction(fn ->
      retrieval = insert_retrieval!(attrs)

      selected
      |> Enum.with_index(1)
      |> Enum.each(&record_retrieved!(&1, context, retrieval.id))

      retrieval
    end)
  end

  defp insert_retrieval!(attrs) do
    Retrieval.create_changeset(%Retrieval{}, attrs) |> Repo.insert() |> unwrap!()
  end

  defp record_retrieved!({%{item: item}, rank}, context, retrieval_id) do
    evidence = %{"retrieval_id" => retrieval_id, "rank" => rank}
    key = "retrieved:#{retrieval_id}:#{item.id}:#{item.version}"
    insert_usage(Repo, item, context, "retrieved", evidence, key) |> unwrap!()
  end

  defp result(%{item: item, document: document}) do
    %{
      id: item.id,
      version: item.version,
      scope: item.scope,
      title: item.title,
      content: document.body,
      citation: "knowledge:#{item.id}@v#{item.version}"
    }
  end

  defp citations(text) when is_binary(text) do
    parsed =
      Regex.scan(~r/knowledge:([0-9a-f-]{36})@v([1-9][0-9]*)/i, text, capture: :all_but_first)
      |> Enum.map(fn [id, version] ->
        %{id: String.downcase(id), version: String.to_integer(version)}
      end)

    {:ok, parsed}
  end

  defp citations(citations) when is_list(citations) do
    Enum.reduce_while(citations, {:ok, []}, fn citation, {:ok, parsed} ->
      case citation do
        %{"id" => id, "version" => version} when is_binary(id) and is_integer(version) ->
          {:cont, {:ok, [%{id: id, version: version} | parsed]}}

        %{id: id, version: version} when is_binary(id) and is_integer(version) ->
          {:cont, {:ok, [%{id: id, version: version} | parsed]}}

        _other ->
          {:halt, {:error, :invalid_knowledge_citation}}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      {:error, _reason} = error -> error
    end
  end

  defp citations(_citations), do: {:error, :invalid_knowledge_citation}

  defp persist_citations(citations, context, _options) do
    Repo.transaction(fn ->
      Enum.each(citations, &persist_citation!(&1, context))
    end)
    |> case do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_citation!(citation, context) do
    with {:ok, item} <- citation_item(citation),
         :ok <- accessible(item, context),
         true <- previously_used?(item, context),
         {:ok, _usage} <-
           insert_usage(
             Repo,
             item,
             context,
             "cited",
             %{"citation" => "knowledge:#{item.id}@v#{item.version}"},
             "cited:#{context.run.id}:#{context.attempt.id}:#{item.id}:#{item.version}"
           ) do
      :ok
    else
      false -> Repo.rollback(:knowledge_citation_not_used_by_stage)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp citation_item(%{id: id, version: version}) do
    case Repo.get(Item, id) do
      %Item{version: ^version} = item -> {:ok, item}
      %Item{} -> {:error, :knowledge_citation_version_mismatch}
      nil -> {:error, :knowledge_item_not_found}
    end
  end

  defp accessible(%Item{scope: "project", project_id: project_id}, context) do
    if project_id == context.project.id, do: :ok, else: {:error, :knowledge_scope_refused}
  end

  defp accessible(%Item{scope: "global", status: "global"}, context) do
    if global_enabled?(context.policy), do: :ok, else: {:error, :knowledge_scope_refused}
  end

  defp accessible(%Item{}, _context), do: {:error, :knowledge_scope_refused}

  defp injectable(%Item{sync_state: "synced", status: status} = item, context)
       when status in ~w(project global) do
    with :ok <- accessible(item, context),
         false <- expired?(item, Cuckoding.Clock.wall_now()),
         false <- superseded?(item) do
      :ok
    else
      true -> {:error, :knowledge_item_not_current}
      {:error, _reason} = error -> error
    end
  end

  defp injectable(%Item{}, _context), do: {:error, :knowledge_item_not_current}

  defp superseded?(item) do
    Repo.exists?(
      from(replacement in Item,
        where:
          replacement.supersedes_id == ^item.id and replacement.sync_state == "synced" and
            replacement.status in ["project", "global"]
      )
    )
  end

  defp previously_used?(item, context) do
    Repo.exists?(
      from(usage in Usage,
        where:
          usage.knowledge_item_id == ^item.id and usage.item_version == ^item.version and
            usage.run_id == ^context.run.id and
            usage.stage_attempt_id == ^context.attempt.id and
            usage.kind in ["injected", "retrieved"]
      )
    )
  end

  defp kind_triggered?(item, triggers) do
    item.kind in triggers or plural(item.kind) in triggers
  end

  defp text_triggered?(item, context) do
    context_tokens =
      tokens([context.attempt.stage_key, context.task.title, context.task.description])

    trigger_tokens = tokens(item.triggers_json)
    overlap(context_tokens, trigger_tokens) > 0
  end

  defp stage_triggers(%{"stages" => stages}, stage_key) when is_list(stages) do
    stages
    |> Enum.find(%{}, &(&1["key"] == stage_key))
    |> Map.get("knowledge_triggers", [])
  end

  defp stage_triggers(_workflow, _stage_key), do: []

  defp global_enabled?(policy) do
    get_in(policy.config_json, ["knowledge", "global_retrieval_enabled"]) == true
  end

  defp namespace(context) do
    suffix = if global_enabled?(context.policy), do: "+global", else: ""
    "project:#{context.project.id}#{suffix}"
  end

  defp expired?(%Item{invalid_at: nil}, _now), do: false
  defp expired?(%Item{invalid_at: invalid_at}, now), do: DateTime.compare(invalid_at, now) != :gt

  defp tokens(values) when is_list(values), do: values |> Enum.join(" ") |> tokens()

  defp tokens(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.split(~r/[^[:alnum:]_]+/u, trim: true)
    |> Enum.reject(&(&1 in @generic_tokens or String.length(&1) < 3))
    |> MapSet.new()
  end

  defp tokens(nil), do: MapSet.new()
  defp overlap(left, right), do: MapSet.intersection(left, right) |> MapSet.size()
  defp plural("decision"), do: "decisions"
  defp plural("observation"), do: "observations"
  defp plural(kind), do: kind <> "s"

  defp result_limit(value) when is_integer(value), do: value |> min(@maximum_results) |> max(1)
  defp result_limit(_value), do: 5

  defp prefix(value, maximum) when byte_size(value) <= maximum, do: value

  defp prefix(value, maximum) do
    value
    |> String.graphemes()
    |> Enum.reduce_while("", fn grapheme, output ->
      if byte_size(output <> grapheme) <= maximum,
        do: {:cont, output <> grapheme},
        else: {:halt, output}
    end)
  end

  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, reason}), do: Repo.rollback(reason)

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
