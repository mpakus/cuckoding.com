defmodule Cuckoding.Projects do
  @moduledoc "Owns project registration, configuration revisions, and repository identity."
end

defmodule Cuckoding.Workflows do
  @moduledoc "Owns workflow definitions, boards, tasks, approvals, and domain transitions."
end

defmodule Cuckoding.Execution do
  @moduledoc "Owns durable commands, runs, attempts, leases, and host execution coordination."
end

defmodule Cuckoding.Adapters do
  @moduledoc "Defines replaceable agent-runtime adapter contracts and normalized results."
end

defmodule Cuckoding.Plugins do
  @moduledoc "Owns plugin discovery, manifests, activation, capabilities, and health."
end

defmodule Cuckoding.Knowledge do
  @moduledoc "Owns project knowledge, provenance, review, publication, and retrieval records."
end

defmodule Cuckoding.Power do
  @moduledoc "Owns power assertions, sleep-gap detection, and wake reconciliation."
end

defmodule Cuckoding.Telemetry do
  @moduledoc "Owns normalized activity, measurements, estimates, and diagnostics."
end

defmodule Cuckoding.Shell do
  @moduledoc "Defines the authenticated boundary between the native shell and control plane."
end
