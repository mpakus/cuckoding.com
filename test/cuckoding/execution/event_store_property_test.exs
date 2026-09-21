defmodule Cuckoding.Execution.EventStorePropertyTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  import Ecto.Query

  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Repo
  alias Ecto.Adapters.SQL.Sandbox

  property "concurrent writers produce a gapless unique sequence" do
    check all(writer_count <- integer(2..8), max_runs: 10) do
      run_id = Ecto.UUID.generate()

      tasks =
        for writer <- 1..writer_count do
          Task.async(fn ->
            Sandbox.unboxed_run(Repo, fn ->
              EventStore.append(run_id, %{
                event_type: "test.writer",
                public_summary: "Writer #{writer}",
                payload: %{"writer" => writer}
              })
            end)
          end)
        end

      # Three 5-second SQLite busy waits must fit before declaring a writer stuck.
      assert Enum.all?(Task.await_many(tasks, 20_000), &match?({:ok, _result}, &1))

      Sandbox.unboxed_run(Repo, fn ->
        sequences =
          Repo.all(
            from(event in RunEvent,
              where: event.run_id == ^run_id,
              order_by: event.sequence,
              select: event.sequence
            )
          )

        assert sequences == Enum.to_list(1..writer_count)
      end)
    end
  end
end
