defmodule BossBackendRecoveryFixture do
  alias Boss.{Deliveries, Projects, Repo, Tasks}
  alias Boss.Deliveries.{Autopilot, AutopilotBatch, Request}

  def run(root, boundary, mode) do
    spawn(fn ->
      Process.sleep(90_000)
      System.halt(3)
    end)

    Mix.start()
    Mix.env(:test)
    Application.put_all_env(Config.Reader.read!("config/config.exs", env: :test))
    Application.put_env(:boss, :data_dir, Path.join(root, "data"))
    Application.put_env(:boss, :spec_auto_sync, false)

    Application.put_env(:boss, Repo,
      database: Path.join(root, "data/boss.db"),
      pool: DBConnection.ConnectionPool,
      pool_size: 2,
      busy_timeout: 5000,
      synchronous: :full
    )

    endpoint = Application.fetch_env!(:boss, BossWeb.Endpoint)

    Application.put_env(
      :boss,
      BossWeb.Endpoint,
      Keyword.merge(endpoint, server: false, secret_key_base: String.duplicate("s", 64))
    )

    Logger.configure(level: :warning)
    System.put_env("TMPDIR", Path.join(root, "tmp"))
    System.put_env("PATH", Path.join(root, "bin") <> ":" <> System.fetch_env!("PATH"))
    System.put_env("BOSS_BACKEND_RECOVERY_ROOT", root)
    System.put_env("BOSS_BACKEND_RECOVERY_BOUNDARY", boundary)
    {:ok, _} = Application.ensure_all_started(:boss)

    if mode == "start" do
      source = Path.join(root, "source")

      project =
        Repo.insert!(%Projects.Project{
          name: "Backend recovery",
          root_path: source,
          git_common_dir: Path.join(source, ".git"),
          specs_path: source,
          base_branch: "main"
        })

      tasks =
        for name <- ~w(one two) do
          {:ok, entry} =
            Projects.record_spec(project.id, %{
              relative_path: "#{name}.md",
              explicit_id: name,
              title: name,
              original_text:
                "---\nid: #{name}\n#{if name == "two", do: "depends_on: [one]\n", else: ""}---\n# #{name}\nCreate result.txt"
            })

          entry.task.id
        end

      {:ok, _} =
        Autopilot.start(project.id, Ecto.UUID.generate(), tasks, "python3 check.py", "codex")

      eventually(fn -> File.exists?(Path.join(root, "processes.json")) end)
      write(root, "before", snapshot())
      Process.sleep(:infinity)
    else
      # Let ordinary scheduling deadlines pass before explicitly attempting Resume.
      Process.sleep(700)
      write(root, "recovered", snapshot())
      batch = Repo.one!(AutopilotBatch)
      delivery = Repo.one!(Deliveries.Delivery)

      {:ok, replay} =
        Autopilot.start(
          batch.project_id,
          batch.command_id,
          batch.task_ids,
          "python3 check.py",
          batch.reviewer
        )

      {:ok, replay_delivery} =
        Deliveries.start(
          delivery.project_id,
          delivery.task_id,
          delivery.command_id,
          "python3 check.py"
        )

      true = replay.id == batch.id and replay_delivery == delivery

      if boundary == "post_check" do
        {:ok, ^delivery} =
          Deliveries.integrate(
            delivery.project_id,
            delivery.id,
            delivery.integration_command_id
          )
      end

      {:error, :busy} =
        Deliveries.start(delivery.project_id, delivery.task_id, Ecto.UUID.generate(), "true")

      {:ok, _} = Autopilot.resume(batch.project_id, batch.id, batch.version)
      eventually(fn -> Repo.one!(AutopilotBatch).status == "blocked" end)
      write(root, "after_resume", snapshot())
      :ok = Application.stop(:boss)
    end
  end

  defp snapshot do
    %{
      vm_pid: System.pid(),
      elixir: System.version(),
      otp: System.otp_release(),
      batch:
        Repo.one!(AutopilotBatch) |> Map.take([:id, :status, :version, :task_ids, :command_id]),
      deliveries:
        Enum.map(Repo.all(Deliveries.Delivery), fn d ->
          Map.take(d, [
            :id,
            :task_id,
            :spec_revision_id,
            :command_id,
            :reviewer,
            :check_config,
            :config_hash,
            :status,
            :cleanup,
            :intent,
            :integration_intent,
            :integration_command_id
          ])
        end),
      tasks:
        Enum.map(
          Repo.all(Tasks.Task),
          &Map.take(&1, [:id, :state, :state_version, :spec_revision_id])
        ),
      requests:
        Enum.map(Repo.all(Request), &Map.take(&1, [:id, :task_id, :status, :delivery_id])),
      steps:
        Enum.map(
          Repo.all(Deliveries.Step),
          &Map.take(&1, [:id, :number, :kind, :status, :input, :receipt])
        ),
      events:
        Enum.map(
          Repo.all(Tasks.Event),
          &Map.take(&1, [:id, :task_id, :command_id, :version, :action, :from_state, :to_state])
        ),
      active: map_size(:sys.get_state(Boss.Runs.Manager).active)
    }
  end

  defp write(root, name, data) do
    path = Path.join(root, name <> ".json")
    File.write!(path <> ".tmp", JSON.encode!(data))
    File.rename!(path <> ".tmp", path)
  end

  defp eventually(predicate, attempts \\ 2000)
  defp eventually(_, 0), do: raise("Fixture did not reach its bounded checkpoint")

  defp eventually(predicate, attempts) do
    if predicate.() do
      :ok
    else
      Process.sleep(20)
      eventually(predicate, attempts - 1)
    end
  end
end

[root, boundary, mode] = System.argv()
BossBackendRecoveryFixture.run(root, boundary, mode)
