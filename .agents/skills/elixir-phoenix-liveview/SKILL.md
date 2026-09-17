---
name: elixir-phoenix-liveview
description: Implement Cuckoding domain, OTP, Ecto, PubSub, and LiveView features with durable state and accessible real-time UI.
---

# Elixir, Phoenix, and LiveView

- Model business transitions in domain contexts, not LiveViews or workers.
- Use supervisors for lifecycle and SQLite for authoritative state.
- Keep transactions short; write event and projection atomically.
- Broadcast only after commit and include a durable sequence number.
- Make LiveViews reconnectable and derive their display from persisted projections.
- Inject clocks (monotonic and wall) so sleep gaps are testable.
- Batch high-frequency metrics and virtualize long streams.
- Add keyboard-accessible controls and explicit command outcomes.

Before completion, run formatter, compile with warnings as errors, tests, and relevant static analysis. Test process crash and LiveView reconnect behavior.
