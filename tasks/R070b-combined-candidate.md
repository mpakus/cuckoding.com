# R070b — Combined candidates for parallel integration

Status: complete, 2026-10-21.

- [x] Add a fixed native operation combining a verified task candidate with the
  current reviewed battle head, under the existing repository lock. Verify exact
  retained identities/ancestry; preserve the source checkout and old candidate.
- [x] Combine only compatible bounded path changes; report overlaps/layout
  conflicts for later workflow repair. Never invoke merge drivers, scripts or
  provider tools. Record exclusive intent/publication/receipt and an app UUID ref;
  uncertain work cannot be replayed or accepted from partial artifacts.
- [x] Verify the combined result and prepare its independent review/check checkout
  through existing native paths; integration still requires the exact current head
  and a separately authorized host review. Do not enable parallel Start yet.
- [x] Closed host normalization, native conflict/tamper/cancellation/source
  preservation tests, relevant quality/build/smoke, docs/AGENTS/README and local
  main merge/branch deletion. State remaining parallel workflow/acceptance plainly.

Evidence: [worklog](../worklog/2026-10-21-R070b-combined-candidate.md).
