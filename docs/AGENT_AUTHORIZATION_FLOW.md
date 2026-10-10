# Agent setup and model catalog

Target experience: connect once, choose models/roles once, reuse across Arenas.
Runtime discovery, version compatibility, authorization and model availability
are separate statuses. None implies the others.

Current R020i provides a roster of named Codex and Cursor connections. Each uses
an independent app-owned profile, observed account status, bounded catalog and
saved model selection. Existing Codex profiles and immutable Team bindings keep
their original identity. Codex's fixed model diagnostic has real GPT-6.1-Sol
response evidence from R020h; Cursor supports setup only, with real signed-in
catalog acceptance still pending. Repository execution remains unavailable.
Login/logout invalidate only that connection's observations before launch.

Login uses a ten-minute managed browser flow. A validated official HTTPS URL is
held only in dispatcher-owned memory; the UI carries a local command link whose
redirect requires a current browser session and active command. URLs, login IDs,
raw provider errors and credentials never enter app tables/events or LiveView
assigns. Closing the browser does not cancel; app interruption does. A matching
completion triggers account/model refresh. Cancellation holds admission through
helper cleanup and leaves status unknown until checked; it cannot undo a provider
completion that raced with Cancel. Expired/interrupted commands never replay.
The native profile lock also refuses overlapping helpers.

**Try a model** selects from a fresh, validated catalog and asks for explicit
provider-usage consent. Changing the selection or connection resets consent. The host picks the
lowest advertised reasoning effort and sends only a fixed acknowledgement prompt
in a private scratch directory, with a two-minute limit and Cancel control.
Permission preflight, model matching and completion validation precede a saved
pass. The UI distinguishes requested from runtime-selected model and retains the
result across reconnects. It is a point-in-time observation, not entitlement or
permission to run repository work. Cancel may follow provider usage; interruption
never automatically resends the prompt. Refreshing the connection clears the
current diagnostic result, retaining its audit history.

## User flow

Open **Agents** to see saved connections, then **Add agent**:

1. **Choose Agent** — name the connection, select Codex or Cursor, and verify its
   executable. Known-location discovery reads metadata only. Additional providers
   remain disabled until their adapters are implemented.
2. **Connect and Authorize** — check or sign in to that private profile. Once
   connected, show refresh/sign-out and hide sign-in. URLs use the protected
   browser redirect; credentials never enter Cuckoding forms.
3. **Select models** — choose from that agent's fresh catalog, including additional
   Codex entries. Never invent model IDs or infer entitlement from a catalog.
   Codex also offers the separately consented optional diagnostic.
4. **Save** — retain an audited selection for this connection. Then **Team** lets
   each role choose its own agent and one of that agent's saved models. A model
   from another connection cannot be submitted as a substitute.

New Arenas inherit the default Team. Existing scoped adoptions and historical
bindings do not change when another agent is added. Codex planning uses the exact
assigned connection; Cursor planning reports unavailable until its execution
boundary is implemented. Saving a mixed team grants no execution permission.

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

Offer a runtime default only if the adapter supports it. The current UI accepts
only validated catalog entries; manual model IDs are unavailable. Never invent a
catalog or silently substitute another model.
A missing/removed selected model blocks the affected role with an explicit
selection action. Retain requested and provider-reported actual models separately.

Cache account-dependent availability under the authorization identity and runtime
version, not a global list shared indiscriminately between accounts. Record
unsupported discovery honestly. Do not persist raw provider payloads/errors.

## Ownership and acceptance

App-owned profiles contain provider-managed state; Cuckoding stores references,
not credentials. Shared authorization may also share provider-managed history;
named connections therefore use separate profiles. Task instructions and permission
settings stay attempt-owned. Disconnect requires confirmation, logs out only that
profile and blocks future launches. An affected-role/Arena preview is still planned. It does not
silently erase work or revoke unrelated personal sign-ins.

For each runtime, verify fresh login, two Arenas, different models, concurrent
sessions, app restart, refresh, revocation and isolated execution. Inspect global
writes and child processes without exposing credentials. If safe profile reuse
or required permissions cannot be demonstrated, the adapter remains unavailable.
See [adapter contract](AGENT_RUNTIME_ADAPTERS.md) and [R020/R090](PLAN.md).
