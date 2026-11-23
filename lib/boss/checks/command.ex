defmodule Boss.Checks.Command do
  @moduledoc "User-entered argv; never infers executable commands from repository or model text."

  def parse(text) when is_binary(text) and byte_size(text) in 1..4096 do
    with true <- String.valid?(text) and not String.contains?(text, [<<0>>, "\n", "\r"]),
         [executable | _] = argv <- OptionParser.split(text),
         true <- executable != "" and length(argv) <= 128 do
      config = %{"argv" => argv, "timeout_ms" => 120_000, "output_limit" => 1_048_576}
      hash = :crypto.hash(:sha256, JSON.encode!([argv, 120_000, 1_048_576]))
      {:ok, config, Base.encode16(hash, case: :lower)}
    else
      _ -> {:error, :invalid_command}
    end
  rescue
    _ in [ArgumentError, RuntimeError] -> {:error, :invalid_command}
  end

  def parse(_), do: {:error, :invalid_command}

  @doc """
  Parses an optional workflow check command. When blank or omitted, returns a
  deterministic `spec_only` verification config so the selected Reviewer verifies
  the candidate directly against the task specification without an external command.
  """
  def parse_workflow(nil), do: spec_only()

  def parse_workflow(text) when is_binary(text) do
    if String.valid?(text) and not String.contains?(text, [<<0>>, "\n", "\r"]) and
         String.trim(text) == "" do
      spec_only()
    else
      parse(text)
    end
  end

  def parse_workflow(_), do: {:error, :invalid_command}

  def spec_only do
    config = %{
      "mode" => "spec_only",
      "argv" => [],
      "timeout_ms" => 120_000,
      "output_limit" => 1_048_576
    }

    hash = :crypto.hash(:sha256, JSON.encode!(["spec_only", 120_000, 1_048_576]))
    {:ok, config, Base.encode16(hash, case: :lower)}
  end

  def spec_only?(%{"mode" => "spec_only"}), do: true
  def spec_only?(%{"argv" => []}), do: true
  def spec_only?(_), do: false

  def describe(config) when is_map(config) do
    if spec_only?(config) do
      "Specification review (no shell check command)"
    else
      case config["argv"] do
        argv when is_list(argv) and argv != [] -> Enum.join(argv, " ")
        _ -> "Specification review"
      end
    end
  end

  def describe(_), do: "Specification review"
end
