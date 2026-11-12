defmodule Boss.Agents.ModelDiscovery do
  @moduledoc """
  Bounded CLI model metadata, reduced to model choices and reported capabilities.
  A catalog describes local CLI configuration and does not prove inference access.
  """
  alias Boss.Agents.Process, as: Runner

  @effort_order ~w(none low medium high xhigh max ultra)
  @model_id ~r/\A[A-Za-z0-9][A-Za-z0-9._:\/@+\[\]-]{0,159}\z/
  @claude_efforts ~w(low medium high xhigh max)

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
      do_fetch(agent_id, executable)
    else
      {:error, :unavailable}
    end
  end

  defp do_fetch(:codex, executable) do
    args = ["--config", "model_provider=\"openai\"", "debug", "models"]

    with {:ok, stdout} <- run_capture(executable, args, 12_000, 1_048_576) do
      parse_codex_models(stdout)
    end
  end

  defp do_fetch(:cursor, executable) do
    with {:ok, stdout} <- run_capture(executable, ["models"], 15_000, 262_144) do
      parse_cursor_models(stdout)
    end
  end

  defp do_fetch(:claude, executable) do
    with {:ok, help} <- run_capture(executable, ["--help"], 5_000, 65_536) do
      {:ok, claude_models(parse_claude_efforts(help))}
    end
  end

  defp do_fetch(:opencode, executable) do
    env = [{"OPENCODE_DISABLE_MODELS_FETCH", "1"}, {"OPENCODE_DISABLE_AUTOUPDATE", "1"}]

    with {:ok, stdout} <-
           run_capture(executable, ["--pure", "models", "--verbose"], 15_000, 4_194_304, env) do
      parse_opencode_models(stdout)
    end
  end

  defp do_fetch(:pi, executable) do
    env = [{"PI_OFFLINE", "1"}]

    with {:ok, stdout} <-
           run_capture(executable, ["--no-extensions", "--list-models"], 10_000, 262_144, env) do
      parse_pi_models(stdout)
    end
  end

  defp do_fetch(:hermes, executable) do
    # Older Hermes versions print detailed credential metadata by default.
    with {:ok, help} <- run_capture(executable, ["status", "--help"], 5_000, 65_536),
         true <- Regex.match?(~r/^\s+--full(?:\s|$)/m, help),
         {:ok, stdout} <- run_capture(executable, ["status"], 5_000, 65_536) do
      parse_hermes_status(stdout)
    else
      false -> {:error, :unavailable}
      error -> error
    end
  end

  defp do_fetch(_other, _executable), do: {:error, :unavailable}

  @doc false
  def parse_codex_models(text) when is_binary(text) do
    with true <- String.valid?(text),
         {:ok, %{"models" => models}} when is_list(models) <- Jason.decode(text) do
      items =
        models
        |> Enum.filter(&match?(%{"visibility" => "list"}, &1))
        |> Enum.filter(&model_id?(&1["slug"]))
        |> Enum.uniq_by(& &1["slug"])
        |> Enum.map(fn m ->
          slug = m["slug"]

          efforts =
            m["supported_reasoning_levels"]
            |> list()
            |> Enum.map(&object(&1)["effort"])
            |> sort_efforts()

          %{
            "id" => slug,
            "name" => label(m["display_name"], slug),
            "reasoning" => efforts != [],
            "reasoning_efforts" => efforts,
            "default_effort" =>
              if(m["default_reasoning_level"] in efforts, do: m["default_reasoning_level"]),
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
      not valid_text?(clean) ->
        {:error, :invalid_models}

      auth_error?(clean) ->
        {:error, :auth_required}

      String.starts_with?(String.downcase(String.trim(clean)), "no models available") ->
        {:ok, []}

      true ->
        items =
          clean
          |> String.split(~r/\R/u)
          |> Enum.map(&String.trim/1)
          |> Enum.flat_map(fn line ->
            with [id, raw_name] <- String.split(line, " - ", parts: 2),
                 true <- model_id?(id) do
              name =
                raw_name
                |> String.replace(~r/\s*\((?:current|default|recommended)\)\s*$/i, "")
                |> String.trim()
                |> label(id)

              reasoning =
                Enum.any?([id, name], fn value ->
                  Regex.match?(
                    ~r/(?:^|[- ])(?:thinking|low|medium|high|xhigh|max|ultra)\z/i,
                    value
                  )
                end)

              [
                %{
                  "id" => id,
                  "name" => name,
                  "reasoning" => reasoning,
                  "reasoning_efforts" => [],
                  "default_effort" => nil,
                  "context_window" => nil,
                  "pricing" => pricing_for(id, nil, "Cursor plan / API")
                }
              ]
            else
              _ -> []
            end
          end)
          |> Enum.uniq_by(& &1["id"])

        if items == [], do: {:error, :invalid_models}, else: {:ok, items}
    end
  end

  @doc false
  def claude_models(efforts \\ @claude_efforts) do
    efforts = sort_efforts(efforts)

    [
      {"opus", "Claude Opus (alias)", @claude_efforts, nil},
      {"sonnet", "Claude Sonnet (alias)", @claude_efforts, nil},
      {"haiku", "Claude Haiku (alias)", [], nil},
      {"claude-opus-4-6", "Claude Opus 4.6", ~w(low medium high max), "high"},
      {"claude-sonnet-4-6", "Claude Sonnet 4.6", ~w(low medium high max), "high"},
      {"claude-haiku-4-5-20251001", "Claude Haiku 4.5", [], nil}
    ]
    |> Enum.map(fn {id, name, supported, default_effort} ->
      available = Enum.filter(efforts, &(&1 in supported))

      %{
        "id" => id,
        "name" => name,
        "reasoning" => available != [],
        "reasoning_efforts" => available,
        "default_effort" => if(default_effort in available, do: default_effort),
        "context_window" => nil,
        "pricing" => if(String.starts_with?(id, "claude-"), do: pricing_for(id, nil))
      }
    end)
  end

  @doc false
  def parse_opencode_models(text) when is_binary(text) do
    clean = strip_ansi(text)

    if valid_text?(clean) do
      case collect_opencode_blocks(String.split(clean, ~r/\r?\n/), []) do
        {:ok, []} when clean != "" ->
          if String.trim(clean) == "", do: {:ok, []}, else: {:error, :invalid_models}

        result ->
          result
      end
    else
      {:error, :invalid_models}
    end
  end

  defp collect_opencode_blocks([], acc),
    do: {:ok, acc |> Enum.reverse() |> Enum.uniq_by(& &1["id"])}

  defp collect_opencode_blocks([header, "{" <> _ = first | rest], acc) do
    if model_id?(header) and String.contains?(header, "/") do
      {json, remaining} = take_opencode_block(first, rest)

      case Jason.decode(json) do
        {:ok, %{} = obj} ->
          collect_opencode_blocks(remaining, [opencode_entry(header, obj) | acc])

        _ ->
          {:error, :invalid_models}
      end
    else
      collect_opencode_blocks([first | rest], acc)
    end
  end

  defp collect_opencode_blocks([line | rest], acc) do
    if model_id?(line) and String.contains?(line, "/") do
      {:error, :invalid_models}
    else
      collect_opencode_blocks(rest, acc)
    end
  end

  defp take_opencode_block("{", rest) do
    # OpenCode's JSON.stringify emits the outer closing brace at column zero.
    case Enum.split_while(rest, &(&1 != "}")) do
      {body, ["}" | remaining]} -> {Enum.join(["{" | body] ++ ["}"], "\n"), remaining}
      _ -> {"", []}
    end
  end

  defp take_opencode_block(line, rest), do: {line, rest}

  defp opencode_entry(full_id, obj) do
    efforts =
      case obj["variants"] do
        v when is_map(v) -> Map.keys(v) |> sort_efforts()
        _ -> []
      end

    reasoning? = object(obj["capabilities"])["reasoning"] == true or efforts != []
    cost = object(obj["cost"])
    ctx = object(obj["limit"])["context"]

    pricing =
      if is_number(cost["input"]) and is_number(cost["output"]) do
        %{
          "input" => cost["input"] * 1.0,
          "output" => cost["output"] * 1.0,
          "cached_input" =>
            case object(cost["cache"])["read"] do
              n when is_number(n) -> n * 1.0
              _ -> nil
            end,
          "unit" => "1M tokens"
        }
      else
        pricing_for(full_id, nil)
      end

    %{
      "id" => full_id,
      "name" => label(obj["name"], full_id),
      "reasoning" => reasoning?,
      "reasoning_efforts" => efforts,
      "default_effort" => nil,
      "context_window" => if(is_integer(ctx) and ctx > 0, do: ctx),
      "pricing" => pricing
    }
  end

  defp parse_claude_efforts(help) do
    case Regex.run(~r/^ +--effort +<[^>]+> +[^\r\n]*\(([^)\r\n]+)\)/m, help) do
      [_, list] ->
        list
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> sort_efforts()

      _ ->
        []
    end
  end

  defp parse_pi_models(text) do
    clean = strip_ansi(text)

    cond do
      not valid_text?(clean) ->
        {:error, :invalid_models}

      String.starts_with?(String.trim(clean), "No models available") ->
        {:ok, []}

      true ->
        rows =
          clean
          |> String.split(~r/\r?\n/, trim: true)
          |> Enum.map(&String.split/1)
          |> Enum.drop_while(&(&1 != ~w(provider model context max-out thinking images)))

        case rows do
          [_header | entries] ->
            items = Enum.map(entries, &pi_entry/1)

            if Enum.all?(items, &is_map/1),
              do: {:ok, Enum.uniq_by(items, & &1["id"])},
              else: {:error, :invalid_models}

          _ ->
            {:error, :invalid_models}
        end
    end
  end

  defp pi_entry([provider, model, context, _max_output, thinking, images])
       when thinking in ["yes", "no"] and images in ["yes", "no"] do
    id = provider <> "/" <> model

    if not String.contains?(provider, "/") and model_id?(id) do
      %{
        "id" => id,
        "name" => model,
        "reasoning" => thinking == "yes",
        "reasoning_efforts" => [],
        "default_effort" => nil,
        "context_window" => pi_context(context),
        "pricing" => nil
      }
    end
  end

  defp pi_entry(_), do: nil

  defp pi_context(context) when byte_size(context) <= 10 do
    case Float.parse(context) do
      {n, "M"} when n > 0 -> round(n * 1_000_000)
      {n, "K"} when n > 0 -> round(n * 1_000)
      {n, ""} when n > 0 -> round(n)
      _ -> nil
    end
  end

  defp pi_context(_), do: nil

  defp parse_hermes_status(text) do
    clean = strip_ansi(text)

    with true <- valid_text?(clean),
         [[_, id]] <- Regex.scan(~r/^ +Model: +([^\r\n]+)\r?$/m, clean),
         [[_, provider]] <- Regex.scan(~r/^ +Provider: +([^\r\n]+)\r?$/m, clean),
         [[_, providers]] <- Regex.scan(~r/^ +Providers: +([^\r\n]+)\r?$/m, clean) do
      cond do
        providers == "none connected" ->
          {:error, :auth_required}

        model_id?(id) and provider in String.split(providers, ", ", trim: true) ->
          {:ok,
           [
             %{
               "id" => id,
               "name" => id,
               "reasoning" => false,
               "reasoning_efforts" => [],
               "default_effort" => nil,
               "context_window" => nil,
               "pricing" => nil
             }
           ]}

        true ->
          {:ok, []}
      end
    else
      _ -> {:error, :invalid_models}
    end
  end

  defp pricing_for(slug, inline, fallback_unit \\ "1M tokens") do
    normalized =
      slug
      |> String.downcase()
      |> String.replace(~r/\A[a-z0-9_-]+\//, "")
      |> String.replace(~r/\A(?:openai|anthropic)\./, "")

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
    valid_text?(text) and
      String.contains?(String.downcase(text), [
        "authentication required",
        "not logged in",
        "please run 'agent login'"
      ])
  end

  defp model_id?(id), do: is_binary(id) and Regex.match?(@model_id, id)
  defp object(value) when is_map(value), do: value
  defp object(_), do: %{}
  defp list(value) when is_list(value), do: value
  defp list(_), do: []

  defp label(name, id) when is_binary(name) do
    if valid_text?(name) and not Regex.match?(~r/[\x00-\x1F\x7F]/, name) and
         String.trim(name) != "",
       do: name,
       else: id
  end

  defp label(_, id), do: id

  defp valid_text?(text), do: String.valid?(text) and not String.contains?(text, <<0>>)

  defp strip_ansi(text) do
    Regex.replace(~r/\e\[[0-9;]*[A-Za-z]/, text, "")
  end

  defp run_capture(executable, args, timeout_ms, limit, env \\ []) do
    scratch = Path.join(System.tmp_dir!(), "boss-agent-models-#{Ecto.UUID.generate()}")

    with :ok <- File.mkdir(scratch) do
      case File.chmod(scratch, 0o700) do
        :ok ->
          capture(executable, args, scratch, timeout_ms, limit, env)

        _ ->
          File.rmdir(scratch)
          {:error, :unavailable}
      end
    else
      _ ->
        {:error, :unavailable}
    end
  end

  defp capture(executable, args, scratch, timeout_ms, limit, env) do
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
          on_event: callback,
          env: env
        )

      if result.cleanup == :group_empty, do: File.rm_rf(scratch)

      if result.cleanup == :group_empty and result.outcome == :exited and
           result.exit_kind == :exit do
        [{:stdout, out_chunks}] = :ets.lookup(capture, :stdout)
        [{:stderr, err_chunks}] = :ets.lookup(capture, :stderr)
        stdout = out_chunks |> Enum.reverse() |> IO.iodata_to_binary()
        stderr = err_chunks |> Enum.reverse() |> IO.iodata_to_binary()

        cond do
          result.exit_code == 0 -> {:ok, stdout}
          auth_error?(stderr <> "\n" <> stdout) -> {:error, :auth_required}
          true -> {:error, :unavailable}
        end
      else
        {:error, :unavailable}
      end
    after
      :ets.delete(capture)
    end
  end
end
