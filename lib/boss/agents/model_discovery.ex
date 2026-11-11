defmodule Boss.Agents.ModelDiscovery do
  @moduledoc """
  Bounded model discovery per authorized CLI agent, returning supported models
  with reasoning capabilities/efforts and reference USD per 1M token pricing.
  """
  alias Boss.Agents.Process, as: Runner

  @effort_order ~w(none low medium high xhigh max ultra)

  # Reference API pricing (USD per 1M tokens: {input, output, cached_input})
  # used when a CLI reports model IDs and reasoning levels without inline dollar rates.
  @reference_pricing %{
    "gpt-6.1-sol" => {2.0, 10.0, 0.10},
    "gpt-6.1-sol-ultrafast" => {12.0, 60.0, 0.60},
    "gpt-6.1-terra" => {1.0, 5.0, 0.05},
    "gpt-6-astra" => {10.0, 50.0, 1.00},
    "gpt-6-astra-ultrafast" => {60.0, 300.0, 6.00},
    "gpt-6-sol" => {2.0, 10.0, 0.20},
    "gpt-6-luna" => {0.10, 0.50, 0.01},
    "gpt-5.6-sol" => {4.0, 20.0, 0.40},
    "gpt-5.6-terra" => {2.0, 12.0, 0.20},
    "gpt-5.6-luna" => {0.20, 1.20, 0.02},
    "gpt-5.5" => {2.0, 8.0, 0.20},
    "gpt-5.4" => {2.0, 8.0, 0.20},
    "gpt-5" => {1.25, 10.0, 0.125},
    "o3" => {2.0, 8.0, 0.50},
    "o4-mini" => {1.10, 4.40, 0.275},
    "gpt-4.1" => {2.0, 8.0, 0.50},
    "gpt-4o" => {2.50, 10.0, 1.25},
    "opus" => {5.0, 25.0, 0.50},
    "sonnet" => {3.0, 15.0, 0.30},
    "haiku" => {1.0, 5.0, 0.10},
    "claude-fable-5-2" => {8.0, 40.0, 0.20},
    "claude-fable-5-1" => {10.0, 50.0, 0.25},
    "claude-fable-5" => {10.0, 50.0, 1.00},
    "claude-opus-5-5" => {4.0, 20.0, 0.20},
    "claude-opus-5" => {5.0, 25.0, 0.50},
    "claude-sonnet-5-5" => {2.0, 10.0, 0.10},
    "claude-sonnet-5" => {2.0, 10.0, 0.20},
    "claude-haiku-5-5" => {0.10, 0.50, 0.01},
    "claude-opus-4-8" => {5.0, 25.0, 0.50},
    "claude-opus-4-7" => {5.0, 25.0, 0.50},
    "claude-opus-4-6" => {5.0, 25.0, 0.50},
    "claude-opus-4-5-20251101" => {5.0, 25.0, 0.50},
    "claude-sonnet-4-6" => {3.0, 15.0, 0.30},
    "claude-sonnet-4-5" => {3.0, 15.0, 0.30},
    "claude-sonnet-4" => {3.0, 15.0, 0.30},
    "claude-sonnet-4-thinking" => {3.0, 15.0, 0.30},
    "claude-haiku-4-5-20251001" => {1.0, 5.0, 0.10},
    "claude-haiku-4-5" => {1.0, 5.0, 0.10},
    "gemini-4-argon" => {2.0, 10.0, 0.10},
    "gemini-2.5-pro" => {1.25, 10.0, 0.31},
    "grok-4.7" => {2.0, 6.0, 0.50},
    "grok-4" => {3.0, 15.0, 0.75},
    "deepseek-v4-pro" => {0.66, 1.98, 0.022},
    "deepseek-r1" => {0.55, 2.19, 0.14}
  }

  def fetch(agent_id, executable) when is_atom(agent_id) do
    if is_binary(executable) and File.regular?(executable) do
      with_scratch(fn scratch ->
        do_fetch(agent_id, executable, scratch)
      end)
    else
      {:ok, []}
    end
  end

  defp do_fetch(:codex, executable, scratch) do
    case run_capture(
           executable,
           ["--config", "model_provider=\"openai\"", "debug", "models"],
           scratch,
           12_000,
           1_048_576
         ) do
      {:ok, 0, stdout, _stderr} ->
        parse_codex_models(stdout)

      {:ok, _code, stdout, stderr} ->
        if auth_error?(stderr <> "\n" <> stdout),
          do: {:error, :auth_required},
          else: {:error, :unavailable}

      error ->
        error
    end
  end

  defp do_fetch(:cursor, executable, scratch) do
    case run_capture(executable, ["models"], scratch, 15_000, 262_144) do
      {:ok, 0, stdout, _stderr} ->
        parse_cursor_models(stdout)

      {:ok, _code, stdout, stderr} ->
        if auth_error?(stderr <> "\n" <> stdout),
          do: {:error, :auth_required},
          else: {:error, :unavailable}

      error ->
        error
    end
  end

  defp do_fetch(:claude, executable, scratch) do
    with {:ok, 0, status_out, _} <-
           run_capture(executable, ["auth", "status", "--json"], scratch, 8_000, 65_536),
         {:ok, %{"loggedIn" => true}} <- Jason.decode(String.trim(status_out)) do
      efforts =
        case run_capture(executable, ["--help"], scratch, 5_000, 65_536) do
          {:ok, 0, help_out, _} -> parse_claude_efforts(help_out)
          _ -> ~w(low medium high xhigh max)
        end

      {:ok, claude_models(efforts)}
    else
      {:ok, _, _, _} -> {:error, :auth_required}
      {:error, :auth_required} -> {:error, :auth_required}
      _ -> {:error, :auth_required}
    end
  end

  defp do_fetch(:opencode, executable, scratch) do
    case run_capture(executable, ["models", "--verbose"], scratch, 15_000, 2_097_152) do
      {:ok, 0, stdout, _stderr} ->
        parse_opencode_models(stdout)

      _ ->
        {:error, :unavailable}
    end
  end

  defp do_fetch(:pi, executable, scratch) do
    with {:ok, 0, help, _} <- run_capture(executable, ["--help"], scratch, 5_000, 65_536),
         true <- String.contains?(help, "--list-models"),
         {:ok, 0, out, _} <- run_capture(executable, ["--list-models"], scratch, 10_000, 262_144) do
      parse_cursor_models(out)
    else
      _ -> {:ok, []}
    end
  end

  defp do_fetch(_other, _executable, _scratch), do: {:ok, []}

  @doc false
  def parse_codex_models(text) when is_binary(text) do
    with true <- String.valid?(text),
         {:ok, %{"models" => models}} when is_list(models) <- Jason.decode(text) do
      items =
        models
        |> Enum.filter(&(is_map(&1) and &1["visibility"] == "list" and is_binary(&1["slug"])))
        |> Enum.map(fn m ->
          slug = m["slug"]

          efforts =
            (m["supported_reasoning_levels"] || [])
            |> Enum.map(&if(is_map(&1), do: &1["effort"]))
            |> Enum.filter(&is_binary/1)
            |> sort_efforts()

          %{
            "id" => slug,
            "name" => m["display_name"] || slug,
            "reasoning" => efforts != [],
            "reasoning_efforts" => efforts,
            "default_effort" => m["default_reasoning_level"],
            "context_window" => if(is_integer(m["context_window"]), do: m["context_window"]),
            "pricing" => pricing_for(slug, m["pricing"])
          }
        end)

      {:ok, items}
    else
      _ -> {:error, :invalid_models}
    end
  end

  @doc false
  def parse_cursor_models(text) when is_binary(text) do
    clean = strip_ansi(text)

    cond do
      auth_error?(clean) ->
        {:error, :auth_required}

      String.contains?(String.downcase(clean), "no models available") ->
        {:ok, []}

      true ->
        items =
          clean
          |> String.split(~r/\R/u)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(
            &(&1 == "" or &1 == "Available models" or String.starts_with?(&1, "Tip:"))
          )
          |> Enum.reduce({[], MapSet.new()}, fn line, {acc, seen} ->
            case Regex.run(~r/\A([A-Za-z0-9][A-Za-z0-9._:\/@-]*)\s+-\s+(.+)\z/, line) do
              [_, id, raw_name] ->
                if MapSet.member?(seen, id) do
                  {acc, seen}
                else
                  name =
                    raw_name
                    |> String.replace(~r/\s*\((?:current|default|recommended)\)\s*$/i, "")
                    |> String.trim()

                  {efforts, reasoning?} = cursor_reasoning(id, name)

                  entry = %{
                    "id" => id,
                    "name" => if(name == "", do: id, else: name),
                    "reasoning" => reasoning?,
                    "reasoning_efforts" => efforts,
                    "default_effort" => if(reasoning?, do: "high"),
                    "context_window" => nil,
                    "pricing" => pricing_for(id, nil, "Cursor plan / API")
                  }

                  {[entry | acc], MapSet.put(seen, id)}
                end

              _ ->
                {acc, seen}
            end
          end)
          |> elem(0)
          |> Enum.reverse()

        {:ok, items}
    end
  end

  @doc false
  def claude_models(efforts \\ ~w(low medium high xhigh max)) do
    efforts = sort_efforts(efforts)

    [
      {"opus", "Claude Opus (latest)", 200_000, "high"},
      {"sonnet", "Claude Sonnet (latest)", 200_000, "high"},
      {"haiku", "Claude Haiku (latest)", 200_000, "medium"},
      {"claude-opus-4-6", "Claude Opus 4.6", 200_000, "high"},
      {"claude-sonnet-4-6", "Claude Sonnet 4.6", 200_000, "medium"},
      {"claude-haiku-4-5-20251001", "Claude Haiku 4.5", 200_000, "medium"}
    ]
    |> Enum.map(fn {id, name, ctx, default_effort} ->
      %{
        "id" => id,
        "name" => name,
        "reasoning" => true,
        "reasoning_efforts" => efforts,
        "default_effort" =>
          if(default_effort in efforts, do: default_effort, else: List.first(efforts)),
        "context_window" => ctx,
        "pricing" => pricing_for(id, nil)
      }
    end)
  end

  @doc false
  def parse_opencode_models(text) when is_binary(text) do
    lines = strip_ansi(text) |> String.split(~r/\R/u)
    {:ok, collect_opencode_blocks(lines, [], 0)}
  end

  defp collect_opencode_blocks([], acc, _count), do: Enum.reverse(acc)
  defp collect_opencode_blocks(_lines, acc, count) when count >= 60, do: Enum.reverse(acc)

  defp collect_opencode_blocks([header, "{" <> _ = first | rest], acc, count) do
    trimmed = String.trim(header)

    if String.contains?(trimmed, "/") do
      {json_lines, remaining} = take_json_block([first | rest], 0, [])

      case Jason.decode(Enum.join(json_lines, "\n")) do
        {:ok, obj} when is_map(obj) ->
          if regional_duplicate?(trimmed) do
            collect_opencode_blocks(remaining, acc, count)
          else
            entry = opencode_entry(trimmed, obj)
            collect_opencode_blocks(remaining, [entry | acc], count + 1)
          end

        _ ->
          collect_opencode_blocks(remaining, acc, count)
      end
    else
      collect_opencode_blocks([first | rest], acc, count)
    end
  end

  defp collect_opencode_blocks([_ | rest], acc, count),
    do: collect_opencode_blocks(rest, acc, count)

  defp take_json_block([], _depth, acc), do: {Enum.reverse(acc), []}

  defp take_json_block([line | rest], depth, acc) do
    opens = count_char(line, ?{)
    closes = count_char(line, ?})
    next_depth = depth + opens - closes

    if next_depth <= 0 do
      {Enum.reverse([line | acc]), rest}
    else
      take_json_block(rest, next_depth, [line | acc])
    end
  end

  defp count_char(bin, target) do
    bin |> :binary.bin_to_list() |> Enum.count(&(&1 == target))
  end

  defp regional_duplicate?(id) do
    Regex.match?(~r/\Aamazon-bedrock\/(?:au|eu|global|in|jp|us|us-gov)\./, id)
  end

  defp opencode_entry(full_id, obj) do
    efforts =
      case obj["variants"] do
        v when is_map(v) -> Map.keys(v) |> sort_efforts()
        _ -> []
      end

    reasoning? = get_in(obj, ["capabilities", "reasoning"]) == true or efforts != []
    cost = obj["cost"]
    ctx = get_in(obj, ["limit", "context"])

    pricing =
      if is_map(cost) and is_number(cost["input"]) and is_number(cost["output"]) do
        %{
          "input" => cost["input"] * 1.0,
          "output" => cost["output"] * 1.0,
          "cached_input" =>
            case get_in(cost, ["cache", "read"]) do
              n when is_number(n) -> n * 1.0
              _ -> nil
            end,
          "unit" => "1M tokens"
        }
      else
        pricing_for(obj["id"] || full_id, nil)
      end

    %{
      "id" => full_id,
      "name" => obj["name"] || full_id,
      "reasoning" => reasoning?,
      "reasoning_efforts" => efforts,
      "default_effort" => List.first(efforts),
      "context_window" => if(is_integer(ctx) and ctx > 0, do: ctx),
      "pricing" => pricing
    }
  end

  defp parse_claude_efforts(help) do
    case Regex.run(~r/--effort\s+<[^>]+>\s+[^\n]*\(([^)]+)\)/, help) do
      [_, list] ->
        list
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> sort_efforts()

      _ ->
        ~w(low medium high xhigh max)
    end
  end

  defp cursor_reasoning(id, name) do
    down = String.downcase(id <> " " <> name)

    cond do
      String.contains?(down, [
        "thinking",
        "gpt-6",
        "gpt-5",
        "o3",
        "o4",
        "opus",
        "sonnet",
        "fable",
        "grok-4",
        "gemini",
        "deepseek-r",
        "deepseek-v4"
      ]) ->
        {~w(low medium high), true}

      true ->
        {[], false}
    end
  end

  defp pricing_for(slug, inline, fallback_unit \\ "1M tokens") do
    normalized =
      slug
      |> String.downcase()
      |> String.replace(~r/\A[a-z0-9_-]+\//, "")
      |> String.replace(~r/\A(?:openai|anthropic)\./, "")
      |> String.replace(~r/-v\d+(?::\d+)?\z/, "")

    cond do
      is_map(inline) and is_number(inline["input"]) and is_number(inline["output"]) ->
        %{
          "input" => inline["input"] * 1.0,
          "output" => inline["output"] * 1.0,
          "cached_input" =>
            if(is_number(inline["cached_input"]), do: inline["cached_input"] * 1.0),
          "unit" => "1M tokens"
        }

      match = Map.get(@reference_pricing, normalized) ->
        {inp, outp, cached} = match
        %{"input" => inp, "output" => outp, "cached_input" => cached, "unit" => "1M tokens"}

      prefix_match =
          Enum.find(@reference_pricing, fn {k, _} -> String.starts_with?(normalized, k) end) ->
        {_, {inp, outp, cached}} = prefix_match
        %{"input" => inp, "output" => outp, "cached_input" => cached, "unit" => "1M tokens"}

      true ->
        %{"input" => nil, "output" => nil, "cached_input" => nil, "unit" => fallback_unit}
    end
  end

  defp sort_efforts(efforts) do
    efforts
    |> Enum.filter(&(&1 in @effort_order))
    |> Enum.uniq()
    |> Enum.sort_by(&Enum.find_index(@effort_order, fn e -> e == &1 end))
  end

  defp auth_error?(text) when is_binary(text) do
    down = String.downcase(text)

    String.contains?(down, "authentication required") or
      String.contains?(down, "not logged in") or
      String.contains?(down, "please run 'agent login'")
  end

  defp strip_ansi(text) do
    Regex.replace(~r/\e\[[0-9;]*[A-Za-z]/, text, "")
  end

  defp with_scratch(fun) do
    scratch = Path.join(System.tmp_dir!(), "boss-agent-models-#{Ecto.UUID.generate()}")

    with :ok <- File.mkdir(scratch),
         :ok <- File.chmod(scratch, 0o700) do
      fun.(scratch)
    else
      _ ->
        File.rm_rf(scratch)
        {:error, :unavailable}
    end
  end

  defp run_capture(executable, args, scratch, timeout_ms, limit) do
    capture = :ets.new(:agent_model_capture, [:set, :public])
    :ets.insert(capture, [{:bytes, 0}, {:stdout, []}, {:stderr, []}])

    try do
      callback = fn
        {stream, bytes} when stream in [:stdout, :stderr] ->
          if :ets.update_counter(capture, :bytes, byte_size(bytes)) <= limit do
            [{^stream, chunks}] = :ets.lookup(capture, stream)
            :ets.insert(capture, {stream, [bytes | chunks]})
            :ok
          else
            :stop
          end

        _ ->
          :ok
      end

      result =
        Runner.run(executable, args,
          cd: scratch,
          input: "",
          timeout_ms: timeout_ms,
          output_limit: limit,
          on_event: callback
        )

      if result.cleanup == :group_empty, do: File.rm_rf(scratch)

      if result.cleanup == :group_empty and result.outcome == :exited and
           result.exit_kind == :exit do
        [{:stdout, out_chunks}] = :ets.lookup(capture, :stdout)
        [{:stderr, err_chunks}] = :ets.lookup(capture, :stderr)
        stdout = out_chunks |> Enum.reverse() |> IO.iodata_to_binary()
        stderr = err_chunks |> Enum.reverse() |> IO.iodata_to_binary()
        {:ok, result.exit_code, stdout, stderr}
      else
        {:error, :unavailable}
      end
    after
      :ets.delete(capture)
    end
  end
end
