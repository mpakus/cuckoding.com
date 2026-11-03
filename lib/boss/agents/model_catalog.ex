defmodule Boss.Agents.ModelCatalog do
  @moduledoc "Bounded CLI model metadata, reduced to immutable role profiles; not entitlement proof."
  alias Boss.Agents.Process, as: Runner

  @strong ~w(gpt-6.1-sol gpt-5.6-sol gpt-6-astra gpt-5.6-terra)
  @resolver ~w(gpt-6-astra gpt-5.6-terra gpt-6.1-sol gpt-5.6-sol)
  @small ~w(gpt-6-luna gpt-5.6-luna)
  @efforts ~w(medium high xhigh)
  @limit 1_048_576

  def discover, do: discover(System.find_executable("codex"))
  def discover(nil), do: {:error, :catalog_unavailable}

  @doc false
  def discover(executable) when is_binary(executable) do
    scratch = Path.join(System.tmp_dir!(), "boss-model-catalog-#{Ecto.UUID.generate()}")

    with :ok <- File.mkdir(scratch) do
      case File.chmod(scratch, 0o700) do
        :ok ->
          probe(executable, scratch)

        _ ->
          File.rmdir(scratch)
          {:error, :catalog_unavailable}
      end
    else
      _ -> {:error, :catalog_unavailable}
    end
  end

  defp probe(executable, scratch) do
    capture = :ets.new(:model_catalog, [:set, :public])
    :ets.insert(capture, [{:bytes, 0}, {:stdout, []}])

    try do
      callback = fn
        {stream, bytes} when stream in [:stdout, :stderr] ->
          if :ets.update_counter(capture, :bytes, byte_size(bytes)) <= @limit do
            if stream == :stdout do
              [{:stdout, chunks}] = :ets.lookup(capture, :stdout)
              :ets.insert(capture, {:stdout, [bytes | chunks]})
            end

            :ok
          else
            :stop
          end

        _ ->
          :ok
      end

      # Match exec --ignore-user-config's default provider without changing its auth account.
      # The CLI may still apply managed configuration or cached catalog metadata.
      result =
        Runner.run(executable, ["--config", "model_provider=\"openai\"", "debug", "models"],
          cd: scratch,
          input: "",
          timeout_ms: 12_000,
          output_limit: @limit,
          on_event: callback
        )

      # Unknown process ownership retains its scratch directory for inspection.
      if result.cleanup == :group_empty, do: File.rm_rf(scratch)

      cond do
        result.cleanup != :group_empty ->
          {:error, :catalog_cleanup_unknown}

        result.outcome == :cancelled and result.reason == :stopped ->
          {:error, :cancelled}

        result.outcome == :exited and result.exit_kind == :exit and result.exit_code == 0 and
            result.eof == %{stdout: true, stderr: true} ->
          [{:stdout, chunks}] = :ets.lookup(capture, :stdout)
          decode(chunks |> Enum.reverse() |> IO.iodata_to_binary())

        true ->
          {:error, :catalog_unavailable}
      end
    after
      :ets.delete(capture)
    end
  end

  def decode(text) when is_binary(text) and byte_size(text) in 1..@limit do
    with true <- String.valid?(text),
         {:ok, object} <- Jason.decode(text, objects: :ordered_objects),
         %{"models" => models} <- object_map(object),
         true <- is_list(models) and length(models) in 1..512,
         models = Enum.map(models, &object_map/1),
         true <- Enum.all?(models, &model_entry?/1),
         slugs = Enum.map(models, & &1["slug"]),
         true <- Enum.uniq(slugs) == slugs,
         {:ok, available} <- available(models) do
      snapshot(available)
    else
      _ -> {:error, :catalog_invalid}
    end
  end

  def decode(_), do: {:error, :catalog_invalid}

  def validate(snapshot) when is_map(snapshot) do
    primary = snapshot["primary"]
    resolver = snapshot["resolver"]
    small = snapshot["small"]
    fallbacks = snapshot["fallbacks"]

    valid =
      Enum.sort(Map.keys(snapshot)) == ~w(fallbacks primary resolver small version) and
        snapshot["version"] === 2 and strong_profile?(primary) and strong_profile?(resolver) and
        primary["model"] != resolver["model"] and
        (is_nil(small) or (profile?(small) and small["model"] in @small)) and
        is_list(fallbacks) and length(fallbacks) in 2..4 and
        Enum.all?(fallbacks, &strong_profile?/1) and
        length(Enum.uniq_by(fallbacks, & &1["model"])) == length(fallbacks) and
        hd(fallbacks)["model"] == primary["model"] and Enum.at(fallbacks, 1) == resolver and
        effort_rank(hd(fallbacks)) >= effort_rank(primary)

    if valid, do: :ok, else: {:error, :catalog_invalid}
  end

  def validate(_), do: {:error, :catalog_invalid}

  def profile?(profile) when is_map(profile),
    do:
      Enum.sort(Map.keys(profile)) == ~w(model reasoning_effort) and
        profile["model"] in (@strong ++ @small) and profile["reasoning_effort"] in @efforts

  def profile?(_), do: false

  defp strong_profile?(profile), do: profile?(profile) and profile["model"] in @strong
  defp effort_rank(profile), do: Enum.find_index(@efforts, &(&1 == profile["reasoning_effort"]))

  defp object_map(%Jason.OrderedObject{values: pairs}) do
    keys = Enum.map(pairs, &elem(&1, 0))
    if Enum.uniq(keys) == keys, do: Map.new(pairs)
  end

  defp object_map(_), do: nil

  defp model_entry?(%{"slug" => slug, "visibility" => visibility}),
    do:
      is_binary(slug) and byte_size(slug) in 1..128 and
        is_binary(visibility) and byte_size(visibility) in 1..32

  defp model_entry?(_), do: false

  defp available(models) do
    models
    |> Enum.filter(&(&1["visibility"] == "list" and &1["slug"] in (@strong ++ @small)))
    |> Enum.reduce_while({:ok, %{}}, fn model, {:ok, acc} ->
      levels = model["supported_reasoning_levels"]

      if is_list(levels) and length(levels) in 1..12 do
        efforts = Enum.map(levels, fn level -> (object_map(level) || %{})["effort"] end)

        if Enum.all?(efforts, &is_binary/1) and Enum.uniq(efforts) == efforts do
          {:cont, {:ok, Map.put(acc, model["slug"], efforts)}}
        else
          {:halt, {:error, :catalog_invalid}}
        end
      else
        {:halt, {:error, :catalog_invalid}}
      end
    end)
  end

  defp snapshot(available) do
    primary = choose(@strong, available, ~w(high xhigh medium))

    resolver =
      choose(@resolver -- [primary && primary["model"]], available, ~w(xhigh high medium))

    if primary && resolver do
      order = [primary["model"], resolver["model"]] ++ @strong

      fallbacks =
        order
        |> Enum.uniq()
        |> Enum.map(&choose([&1], available, ~w(xhigh high medium)))
        |> Enum.reject(&is_nil/1)

      {:ok,
       %{
         "version" => 2,
         "primary" => primary,
         "resolver" => resolver,
         "small" => choose(@small, available, ~w(medium high xhigh)),
         "fallbacks" => fallbacks
       }}
    else
      {:error, :catalog_insufficient_models}
    end
  end

  defp choose(models, available, efforts) do
    Enum.find_value(models, fn model ->
      if effort = Enum.find(efforts, &(&1 in Map.get(available, model, []))),
        do: %{"model" => model, "reasoning_effort" => effort}
    end)
  end
end
