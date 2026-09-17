defmodule Cuckoding.Execution.CommandPolicy do
  @moduledoc """
  Loads trusted project command policy and executes only named declarations.

  Declarations are tokenized without a shell, resolved to an absolute executable,
  and passed to the configured `RunnerBridge`.
  """

  alias Cuckoding.Execution.LocalProcessRunner
  alias Cuckoding.Execution.Run
  alias Cuckoding.Projects.ProjectConfigVersion
  alias Cuckoding.Repo

  @max_config_bytes 1_048_576
  @command_key ~r/^[a-z][a-z0-9_]*$/
  @shells ~w(sh bash zsh csh tcsh fish dash ksh)

  @fields [
    %{path: "commands", label: "Declared commands", classification: :enforced},
    %{
      path: "repository.protected_paths",
      label: "Protected paths",
      classification: :enforced
    },
    %{path: "ports.range", label: "Preview port range", classification: :enforced},
    %{
      path: "network.default_class",
      label: "Network class",
      classification: :advisory
    },
    %{
      path: "resources.per_run.memory_mb_ceiling",
      label: "Memory ceiling",
      classification: :advisory
    }
  ]

  @doc "Loads, validates, and hashes one project YAML document."
  def load_project(path) when is_binary(path) do
    with {:ok, %{type: :regular, size: size}} when size <= @max_config_bytes <- File.lstat(path),
         {:ok, config} when is_map(config) <- YamlElixir.read_from_file(path),
         :ok <- validate(config),
         {:ok, contents} <- File.read(path) do
      {:ok, %{config: config, source_hash: sha256(contents)}}
    else
      {:ok, %{size: size}} when size > @max_config_bytes ->
        {:error, :config_too_large}

      {:ok, _stat} ->
        {:error, :config_not_regular_file}

      {:error, %YamlElixir.ParsingError{} = error} ->
        {:error, {:invalid_yaml, Exception.message(error)}}

      {:error, reason} ->
        {:error, reason}

      _other ->
        {:error, :invalid_project_config}
    end
  end

  def load_project(_path), do: {:error, :invalid_project_config_path}

  @doc "Validates the security-sensitive project command and protected-path fields."
  def validate(config) when is_map(config) do
    with 2 <- config["schema_version"],
         commands when is_map(commands) <- config["commands"],
         :ok <- validate_commands(commands),
         protected when is_list(protected) <- get_in(config, ["repository", "protected_paths"]),
         {:ok, _paths} <- Cuckoding.Execution.ProtectedPaths.normalize(protected) do
      :ok
    else
      nil -> {:error, :missing_required_policy_field}
      false -> {:error, :invalid_project_config}
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_project_config}
    end
  end

  def validate(_config), do: {:error, :invalid_project_config}

  @doc "Returns UI-ready labels for configured enforced and advisory fields."
  def classified_fields(config) when is_map(config) do
    Enum.filter(@fields, &configured?(config, &1.path))
  end

  @doc "Resolves a command from the immutable trusted snapshot attached to a run."
  def resolve(%Run{} = run, command_key) when is_binary(command_key) do
    with {:ok, snapshot} <- policy_snapshot(run),
         :ok <- validate(snapshot.config_json),
         {:ok, declaration} <- declared_command(snapshot.config_json, command_key),
         {:ok, argv} <- declaration_argv(declaration),
         {:ok, executable} <- executable(hd(argv)),
         :ok <- safe_arguments(tl(argv)) do
      {:ok, %{executable: executable, args: tl(argv), role: "declared_command:#{command_key}"}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def resolve(%Run{}, command_key), do: {:error, {:invalid_command_key, command_key}}

  @doc "Executes a declared command through the selected runner."
  def execute(%Run{} = run, environment, command_key, options \\ []) do
    invoke(:exec, run, environment, command_key, options)
  end

  @doc "Starts a declared command through the selected runner."
  def start(%Run{} = run, environment, command_key, options \\ []) do
    invoke(:start, run, environment, command_key, options)
  end

  defp invoke(operation, run, environment, command_key, options) do
    runner = Keyword.get(options, :runner, LocalProcessRunner)
    runner_options = Keyword.delete(options, :runner)

    if environment.run_id == run.id do
      with {:ok, command} <- resolve(run, command_key),
           do: apply(runner, operation, [environment, command, runner_options])
    else
      {:error, :environment_run_mismatch}
    end
  end

  defp validate_commands(commands) when map_size(commands) > 0 do
    Enum.reduce_while(commands, :ok, fn {key, declaration}, :ok ->
      with true <- is_binary(key) and Regex.match?(@command_key, key),
           {:ok, argv} <- declaration_argv(declaration),
           {:ok, _executable} <- executable(hd(argv)),
           :ok <- safe_arguments(tl(argv)) do
        {:cont, :ok}
      else
        false -> {:halt, {:error, {:invalid_command_key, key}}}
        {:error, reason} -> {:halt, {:error, {key, reason}}}
      end
    end)
  end

  defp validate_commands(_commands), do: {:error, :commands_must_not_be_empty}

  defp policy_snapshot(run) do
    case Repo.get(ProjectConfigVersion, run.policy_snapshot_id) do
      %ProjectConfigVersion{trusted_at: nil} -> {:error, :policy_snapshot_not_trusted}
      %ProjectConfigVersion{} = snapshot -> {:ok, snapshot}
      nil -> {:error, :policy_snapshot_not_found}
    end
  end

  defp declared_command(config, key) do
    case get_in(config, ["commands", key]) do
      nil -> {:error, {:command_not_declared, key}}
      declaration -> {:ok, declaration}
    end
  end

  defp declaration_argv(command) when is_binary(command) do
    case OptionParser.split(command) do
      [] -> {:error, :empty_command}
      argv -> {:ok, argv}
    end
  rescue
    ArgumentError -> {:error, :invalid_command_syntax}
  end

  defp declaration_argv(argv) when is_list(argv) do
    if argv != [] and Enum.all?(argv, &is_binary/1),
      do: {:ok, argv},
      else: {:error, :invalid_command_argv}
  end

  defp declaration_argv(_declaration), do: {:error, :invalid_command_declaration}

  defp executable(program) do
    resolved =
      if Path.type(program) == :absolute,
        do: program,
        else: System.find_executable(program)

    cond do
      not is_binary(resolved) -> {:error, {:executable_not_found, program}}
      Path.basename(resolved) in @shells -> {:error, :shell_commands_not_allowed}
      not File.regular?(resolved) -> {:error, {:executable_not_found, program}}
      true -> {:ok, Path.expand(resolved)}
    end
  end

  defp safe_arguments(arguments) do
    Enum.find_value(arguments, :ok, fn argument ->
      candidate = argument |> String.split("=", parts: 2) |> List.last()

      cond do
        String.contains?(argument, <<0>>) -> {:error, :nul_argument}
        Path.type(candidate) == :absolute -> {:error, {:outside_worktree_path, argument}}
        ".." in Path.split(candidate) -> {:error, {:outside_worktree_path, argument}}
        true -> false
      end
    end)
  end

  defp configured?(config, path) do
    path
    |> String.split(".")
    |> Enum.reduce_while(config, fn key, value ->
      case value do
        %{^key => next} -> {:cont, next}
        _other -> {:halt, nil}
      end
    end)
    |> is_nil()
    |> Kernel.not()
  end

  defp sha256(contents), do: :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)
end

defmodule Cuckoding.Execution.ProtectedPaths do
  @moduledoc "Detects protected paths in commit ranges and working-tree changes."

  import Ecto.Query

  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.Run
  alias Cuckoding.Projects.ProjectConfigVersion
  alias Cuckoding.Repo
  alias Cuckoding.Workflows.Approval

  @git "/usr/bin/git"
  @always_protected ".cuckoding"

  @doc "Normalizes configured protected paths and always includes `.cuckoding`."
  def normalize(paths) when is_list(paths) do
    paths
    |> Enum.reduce_while({:ok, [@always_protected]}, fn path, {:ok, accepted} ->
      case normalize_path(path) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | accepted]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, accepted} -> {:ok, accepted |> Enum.uniq() |> Enum.sort()}
      error -> error
    end
  end

  def normalize(_paths), do: {:error, :invalid_protected_paths}

  @doc "Returns protected files changed since the environment's frozen base, including dirty files."
  def scan(%Environment{} = environment, configured_paths) do
    with {:ok, protected} <- normalize(configured_paths),
         {:ok, root} <- repository_root(environment.worktree_path),
         {:ok, committed} <- diff_paths(root, [environment.base_sha, "HEAD"]),
         {:ok, unstaged} <- diff_paths(root, []),
         {:ok, staged} <- diff_paths(root, ["--cached"]),
         {:ok, untracked} <- untracked_paths(root) do
      changed = Enum.uniq(committed ++ unstaged ++ staged ++ untracked)
      {:ok, Enum.filter(changed, &protected?(&1, protected)) |> Enum.sort()}
    end
  end

  @doc "Blocks QA on an exact protected-path change set until its scoped approval is approved."
  def gate_qa(%Run{} = run, stage_attempt_id, %Environment{} = environment) do
    with %ProjectConfigVersion{} = snapshot <-
           Repo.get(ProjectConfigVersion, run.policy_snapshot_id),
         true <- not is_nil(snapshot.trusted_at),
         paths when is_list(paths) <-
           get_in(snapshot.config_json, ["repository", "protected_paths"]),
         {:ok, changed} <- scan(environment, paths) do
      gate_change_set(run, stage_attempt_id, changed)
    else
      nil -> {:error, :policy_snapshot_not_found}
      false -> {:error, :policy_snapshot_not_trusted}
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_protected_path_policy}
    end
  end

  defp gate_change_set(_run, _stage_attempt_id, []), do: {:ok, %{protected_paths: []}}

  defp gate_change_set(run, stage_attempt_id, changed) do
    digest = digest(changed)
    kind = "protected_path_change:#{digest}"

    case Repo.one(
           from(approval in Approval,
             where:
               approval.run_id == ^run.id and approval.stage_attempt_id == ^stage_attempt_id and
                 approval.kind == ^kind,
             order_by: [desc: approval.inserted_at],
             limit: 1
           )
         ) do
      %Approval{decision: "approved"} = approval ->
        {:ok, %{approval: approval, protected_paths: changed}}

      %Approval{decision: "pending"} = approval ->
        {:approval_required, %{approval: approval, protected_paths: changed}}

      %Approval{decision: "rejected"} = approval ->
        {:approval_rejected, %{approval: approval, protected_paths: changed}}

      nil ->
        request_approval(run, stage_attempt_id, kind, digest, changed)
    end
  end

  defp request_approval(run, stage_attempt_id, kind, digest, changed) do
    attrs = %{
      event_type: "policy.protected_paths_flagged",
      public_summary: "Protected path changes require approval before QA",
      payload: %{"approval_kind" => kind, "change_digest" => digest, "paths" => changed}
    }

    projection = fn repo, _sequence ->
      query =
        from(approval in Approval,
          where:
            approval.run_id == ^run.id and approval.stage_attempt_id == ^stage_attempt_id and
              approval.kind == ^kind,
          order_by: [desc: approval.inserted_at],
          limit: 1
        )

      case repo.one(query) do
        %Approval{} = approval ->
          {:ok, approval}

        nil ->
          Approval.create_changeset(%Approval{}, %{
            id: Cuckoding.Identifier.generate(),
            run_id: run.id,
            stage_attempt_id: stage_attempt_id,
            kind: kind
          })
          |> repo.insert()
      end
    end

    case EventStore.append(run.id, attrs, projection) do
      {:ok, {_event, approval}} ->
        {:approval_required, %{approval: approval, protected_paths: changed}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp diff_paths(root, suffix) do
    git(
      root,
      ["-c", "core.quotepath=false", "diff", "--name-status", "-z", "-M" | suffix] ++ ["--"]
    )
    |> parse_name_status()
  end

  defp untracked_paths(root) do
    with {:ok, output} <- git(root, ["ls-files", "--others", "--exclude-standard", "-z"]) do
      {:ok, split_nul(output)}
    end
  end

  defp parse_name_status({:error, reason}), do: {:error, reason}

  defp parse_name_status({:ok, output}) do
    output
    |> split_nul()
    |> parse_entries([])
  end

  defp parse_entries([], paths), do: {:ok, Enum.reverse(paths)}

  defp parse_entries([<<kind, _rest::binary>>, old_path, new_path | rest], paths)
       when kind in [?R, ?C],
       do: parse_entries(rest, [new_path, old_path | paths])

  defp parse_entries([_status, path | rest], paths), do: parse_entries(rest, [path | paths])
  defp parse_entries(_tokens, _paths), do: {:error, :invalid_git_name_status}

  defp split_nul(output),
    do: output |> :binary.split(<<0>>, [:global]) |> Enum.reject(&(&1 == ""))

  defp protected?(path, protected) do
    Enum.any?(protected, &(path == &1 or String.starts_with?(path, &1 <> "/")))
  end

  defp normalize_path(path) when is_binary(path) do
    normalized = path |> String.trim() |> String.trim_trailing("/")

    cond do
      normalized == "" -> {:error, :empty_protected_path}
      String.contains?(normalized, <<0>>) -> {:error, :invalid_protected_path}
      Path.type(normalized) == :absolute -> {:error, {:outside_worktree_path, path}}
      "." in Path.split(normalized) -> {:error, {:invalid_protected_path, path}}
      ".." in Path.split(normalized) -> {:error, {:outside_worktree_path, path}}
      true -> {:ok, normalized}
    end
  end

  defp normalize_path(path), do: {:error, {:invalid_protected_path, path}}

  defp repository_root(path) do
    with {:ok, expanded} <- canonical_directory(path),
         {:ok, root} <- git(expanded, ["rev-parse", "--show-toplevel"]),
         {:ok, root} <- canonical_directory(String.trim(root)),
         true <- root == expanded do
      {:ok, root}
    else
      false -> {:error, :repository_root_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  defp canonical_directory(path) do
    expanded = Path.expand(path)

    case File.stat(expanded) do
      {:ok, %{type: :directory}} ->
        case System.cmd("/bin/pwd", ["-P"], cd: expanded, stderr_to_stdout: true) do
          {resolved, 0} -> {:ok, String.trim(resolved)}
          {_output, _status} -> {:error, :path_resolution_failed}
        end

      {:ok, _stat} ->
        {:error, :not_a_directory}

      {:error, :enoent} ->
        {:error, :missing_directory}

      {:error, reason} ->
        {:error, {:path_inspection_failed, reason}}
    end
  end

  defp git(root, args) do
    case System.cmd(@git, ["-C", root | args], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, status} -> {:error, {:git_failed, status, String.trim(output)}}
    end
  end

  defp digest(paths) do
    :crypto.hash(:sha256, Enum.join(paths, <<0>>))
    |> Base.encode16(case: :lower)
  end
end
