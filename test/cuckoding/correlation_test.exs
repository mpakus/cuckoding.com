defmodule Cuckoding.CorrelationTest do
  use ExUnit.Case, async: true

  alias Cuckoding.Correlation

  test "captured context crosses a process boundary and restores prior metadata" do
    Correlation.put("outer")
    context = Correlation.capture()

    task =
      Task.async(fn ->
        Correlation.put("child-before")

        inside = Correlation.with_context(context, &Correlation.current/0)
        {inside, Correlation.current()}
      end)

    assert Task.await(task) == {"outer", "child-before"}
    assert Correlation.current() == "outer"
  end

  test "telemetry metadata includes the current correlation id" do
    handler_id = {__MODULE__, make_ref()}
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:cuckoding, :test, :event],
        fn event, measurements, metadata, _config ->
          send(test_pid, {event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    Correlation.put("telemetry-0103")
    Correlation.execute([:cuckoding, :test, :event], %{count: 1}, %{kind: :test})

    assert_receive {[:cuckoding, :test, :event], %{count: 1}, metadata}
    assert metadata == %{correlation_id: "telemetry-0103", kind: :test}
  end
end
