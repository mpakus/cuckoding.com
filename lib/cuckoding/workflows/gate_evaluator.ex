defmodule Cuckoding.Workflows.GateEvaluator do
  @moduledoc "Validates the typed evidence bundle and evaluates release exit gates."

  @artifact_types ~w(specification role_report qa_report evidence_bundle release_receipt)
  @statuses ~w(passed failed)
  @severities ~w(info warning error blocker)

  @doc "Returns a validated bundle or a failed outcome with structured findings."
  def evaluate(
        %{
          "schema_version" => 1,
          "run_id" => run_id,
          "branch" => branch,
          "base_sha" => base_sha,
          "head_sha" => head_sha,
          "artifacts" => artifacts,
          "tests" => tests,
          "findings" => findings,
          "knowledge_citations" => citations
        } = bundle
      )
      when is_binary(run_id) and is_binary(branch) and is_binary(base_sha) and
             is_binary(head_sha) and is_list(artifacts) and is_list(tests) and
             is_list(findings) and is_list(citations) do
    with :ok <- validate_artifacts(artifacts),
         :ok <- validate_tests(tests),
         :ok <- validate_findings(findings),
         :ok <- validate_citations(citations) do
      failed = failed_test_findings(tests) ++ blocking_findings(findings)

      if failed == [],
        do: {:ok, bundle},
        else: {:error, %{"outcome" => "failed", "findings" => failed}}
    else
      {:error, reason} -> validation_failure(reason)
    end
  end

  def evaluate(_bundle), do: validation_failure("invalid evidence bundle schema")

  @doc "Evaluates a bundle and verifies every referenced file against its SHA-256 digest."
  def verify(bundle, run_dir) when is_binary(run_dir) do
    with {:ok, validated} <- evaluate(bundle),
         :ok <- verify_descriptors(run_dir, "artifacts", validated["artifacts"]),
         :ok <- verify_descriptors(run_dir, nil, validated["knowledge_citations"]) do
      {:ok, validated}
    else
      {:error, %{"outcome" => "failed"}} = error -> error
      {:error, reason} -> validation_failure(reason)
    end
  end

  defp validate_artifacts([]), do: {:error, "evidence bundle has no artifacts"}

  defp validate_artifacts(artifacts) do
    validate_items(artifacts, "artifact", fn artifact ->
      valid_descriptor?(artifact) and artifact["type"] in @artifact_types
    end)
  end

  defp validate_tests([]), do: {:error, "evidence bundle has no test results"}

  defp validate_tests(tests) do
    validate_items(tests, "test result", fn result ->
      is_map(result) and nonempty?(result["command"]) and result["status"] in @statuses and
        nonnegative?(result["passed"]) and nonnegative?(result["failed"])
    end)
  end

  defp validate_findings(findings) do
    validate_items(findings, "finding", fn finding ->
      is_map(finding) and finding["severity"] in @severities and
        nonempty?(finding["category"]) and nonempty?(finding["summary"]) and
        is_map(finding["evidence"])
    end)
  end

  defp validate_citations([]), do: {:error, "evidence bundle has no knowledge citations"}

  defp validate_citations(citations) do
    validate_items(citations, "knowledge citation", &valid_descriptor?/1)
  end

  defp validate_items(items, label, validator) do
    case Enum.find_index(items, &(not validator.(&1))) do
      nil -> :ok
      index -> {:error, "invalid #{label} at index #{index}"}
    end
  end

  defp verify_descriptors(run_dir, prefix, descriptors) do
    Enum.reduce_while(descriptors, :ok, fn descriptor, :ok ->
      relative = if prefix, do: Path.join(prefix, descriptor["path"]), else: descriptor["path"]
      path = Path.expand(relative, run_dir)

      result =
        with true <- String.starts_with?(path, Path.expand(run_dir) <> "/"),
             {:ok, %{type: :regular}} <- File.lstat(path),
             {:ok, contents} <- File.read(path),
             digest = :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower),
             true <- digest == descriptor["sha256"] do
          :ok
        else
          _reason -> {:error, "artifact integrity check failed for #{relative}"}
        end

      case result do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp valid_descriptor?(descriptor) do
    is_map(descriptor) and safe_relative_path?(descriptor["path"]) and
      is_binary(descriptor["sha256"]) and
      Regex.match?(~r/\A[0-9a-f]{64}\z/, descriptor["sha256"])
  end

  defp safe_relative_path?(path) when is_binary(path) and path != "" do
    Path.type(path) == :relative and ".." not in Path.split(path)
  end

  defp safe_relative_path?(_path), do: false
  defp nonempty?(value), do: is_binary(value) and value != ""
  defp nonnegative?(value), do: is_integer(value) and value >= 0

  defp failed_test_findings(tests) do
    for %{"status" => "failed"} = result <- tests do
      %{
        "severity" => "error",
        "category" => "qa",
        "summary" => "QA command failed: #{result["command"]}",
        "evidence" => result
      }
    end
  end

  defp blocking_findings(findings),
    do: Enum.filter(findings, &(&1["severity"] in ~w(error blocker)))

  defp validation_failure(reason) do
    {:error,
     %{
       "outcome" => "failed",
       "findings" => [
         %{
           "severity" => "blocker",
           "category" => "artifact_schema",
           "summary" => reason,
           "evidence" => %{}
         }
       ]
     }}
  end
end
