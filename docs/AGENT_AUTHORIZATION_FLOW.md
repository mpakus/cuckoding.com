# Agent setup and model catalog

Target experience: connect once, choose models/roles once, reuse across Arenas.
Runtime discovery, version compatibility, authorization and model availability
are separate statuses. None implies the others.

## User flow

1. **Add agent** suggests known installed runtimes and an editable absolute path.
   Discovery checks known paths/file metadata; it does not execute candidates,
   scan the home directory or read credentials.
2. A fixed adapter version probe verifies compatibility, then **Authorize** opens
   the provider-supported login for an app-owned profile. Show progress and a
   copyable instruction only when the provider needs it. Never ask users to paste
   credentials into CCoding forms.
3. Probe authorization with that same profile and launch configuration. A login
   status result must be followed by an isolated real-session check in adapter
   acceptance; historical status alone cannot prove work will launch.
4. On success, fetch and normalize available model IDs, labels and supported
   options. Store the catalog in SQLite with source, scope and timestamp.
5. Save a human-readable agent name; role forms choose this connection and model.
   Different roles may select different models using the same authorization.
   Choose the three delivery roles and the distinct Summa Rudis coordinator.
6. New Arenas inherit the default team. Starting work checks each distinct
   connection once and shows a targeted reconnect action when necessary.

The normal path does not reassign agents per task or ask for another login on
each app launch. Provider expiry/revocation remains authoritative; there is no
app promise of permanent authorization.

## Discovery behavior

Refresh after successful authorization, on user request, and when the selected
catalog is stale at start. Initial freshness default: 24 hours, recorded as a
product setting. Deduplicate concurrent refreshes per connection/runtime.
Keep a last-good catalog on temporary failure, mark it stale and show the last
successful refresh time. A catalog error does not turn a valid login into a
failed login.

Offer a runtime default only if the adapter supports it. Manual model IDs are an
advanced fallback with format and availability validation; label them unverified
until checked. Never invent a catalog or silently substitute another model.
A missing/removed selected model blocks the affected role with an explicit
selection action. Retain requested and provider-reported actual models separately.

Cache account-dependent availability under the authorization identity and runtime
version, not a global list shared indiscriminately between accounts. Record
unsupported discovery honestly. Do not persist raw provider payloads/errors.

## Ownership and acceptance

App-owned profiles contain provider-managed state; CCoding stores references,
not credentials. Shared authorization may also share provider-managed history;
explain this and support separate profiles. Task instructions and permission
settings stay attempt-owned. Disconnect shows all affected roles/Arenas, requires
confirmation, logs out only that profile and blocks future launches. It does not
silently erase work or revoke unrelated personal sign-ins.

For each runtime, verify fresh login, two Arenas, different models, concurrent
sessions, app restart, refresh, revocation and isolated execution. Inspect global
writes and child processes without exposing credentials. If safe profile reuse
or required permissions cannot be demonstrated, the adapter remains unavailable.
See [adapter contract](AGENT_RUNTIME_ADAPTERS.md) and [R020/R090](PLAN.md).
