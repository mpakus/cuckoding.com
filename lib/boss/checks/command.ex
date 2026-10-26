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
end
