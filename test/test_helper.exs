ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Boss.Repo, :manual)

ExUnit.after_suite(fn _result ->
  directory = Application.fetch_env!(:boss, :data_dir)
  Application.stop(:boss)
  File.rm_rf!(directory)
end)
