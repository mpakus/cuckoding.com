defmodule Cuckoding.HealthTest do
  use ExUnit.Case, async: true

  test "distinguishes application health from dependency health" do
    assert Cuckoding.Health.overall_status(:ok, %{pubsub: :ok}) == :ok
    assert Cuckoding.Health.overall_status(:ok, %{pubsub: :unavailable}) == :degraded
    assert Cuckoding.Health.overall_status(:unavailable, %{pubsub: :ok}) == :degraded
  end

  test "reports the running application and dependencies" do
    health = Cuckoding.Health.snapshot()

    assert health.status == :ok
    assert health.application.status == :ok
    assert health.dependencies == %{pubsub: :ok, web_endpoint: :ok}
  end
end
