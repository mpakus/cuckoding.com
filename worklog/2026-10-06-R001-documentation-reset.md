# R001 — Documentation reset

Date: 2026-10-06. Status: complete for documentation; application unimplemented.
Task: [R001](../tasks/R001-documentation-reset.md).
Branch: `feature/r001-arena-reset`. The user's implementation request now
authorizes committing this completed reset and merging it into local `main`
before R010. No push, native build or restart belongs to R001.

## Acceptance and baseline

The user requested their eight-step story summarized, current docs compressed,
new Arena/Tabula/battle/Secutor/Summa Rudis naming and process, and an ordered
implementation checklist while retaining the stack and RTK/Ponytail.

On arrival, `rtk git status --short --branch` showed main with 700 deleted
tracked files and no other modifications. All 700 were preserved. The surviving
docs comprised 44 Markdown files and 92,233 whitespace-delimited words.
A read-only inventory was saved outside the repo at
`/tmp/cuckoding-r001-baseline.json` for deletion/size verification.

## Changes and scope

- Replaced competing old flows with one saved-team → Arena → Tabula → tasks →
  Start battle flow. Secutor judges; Summa Rudis coordinates; the host validates.
- Specified reusable authorization/models, custom roles/columns, in-scope repair,
  independent review, controls, parallel workers and serialized reviewed integration.
- Retained stack and safety requirements; protected old app data independently of
  the source reset. All application acceptance items stay pending.
- Reduced docs to **16 files / 11,174 words**, **87.9% fewer words**.
- Removed 28 superseded docs and 13 stale root/config/template/pipeline files;
  replacements include four canonical role templates and current Cursor rules.
  The [audit](../docs/DOCUMENTATION_AUDIT.md) maps removals to surviving contracts.
- Updated nine existing skill bodies narrowly; kept all 13 local skills.
  Deferred knowledge/plugin guidance cannot expand rebuild scope.
- Removed XERJ from active workflows/config. Direct RTK file search suffices.
  No plugin, provider, dependency or replacement service was installed.

## Guidance and source review

Read RTK guidance, Ponytail full 4.13.0 (MIT), relevant workflow/architecture/
runner/adapter/security/quality skills and skill-creator for the narrow skill
edits. Inspected all surviving documentation headings and supporting configuration,
then read affected product/flow/architecture/data/auth/execution/security contracts.
Earlier memory identified prior decisions only; the user reset supersedes old
sequential-only behavior and historical acceptance.

`rtk --version`: **0.49.0**.
`rtk git switch -c feature/r001-arena-reset`: passed.
Exact source reads and bulk documentation writes used `rtk proxy cat`,
`rtk proxy sed`, `rtk proxy python3`, and the patch tool. These proxy exceptions
preserve complete Markdown or machine-readable data that RTK's text filters can
truncate. Source/protocol inspection does not grant execution authority.

## Verification results

| Check | Result |
| --- | --- |
| Local references, contract paths, fences | Final recheck: 39 text files, 61 local links passed |
| Intentional deletion preservation | All 700 original missing tracked files remain missing; no implementation restored |
| Plan claim validation | R010–R100 acceptance remains unchecked; only documentation task completed |
| Name/flow review | Current roles/terms agree across docs, prompts and contributor rules; obsolete names occur only in audit history |
| User-story review | PLAN maps all eight steps; parallel execution and all requested provider targets retained |
| Local skill structural validation | 13/13 passed with Ruby safe YAML plus name/description/field/placeholder checks |
| `rtk git diff --check` | Passed |
| Application/compiler/LiveView/native/provider checks | Unavailable: implementation and build sources intentionally absent; no runtime result claimed |

The official skill validator was attempted under system Python and the existing
bundled Python. Both failed at import with `ModuleNotFoundError: No module named
'yaml'`; no dependency was installed to repair a documentation-only check.
The following native Ruby fallback passed all 13 skills. This is structural
validation, not behavioral testing of the skills.

```sh
rtk proxy ruby -ryaml - <<'CUCKODING_SKILLS'
failures = []
files = Dir['.agents/skills/*/SKILL.md'].sort
files.each do |path|
  text = File.read(path)
  match = /\A---\n(.*?)\n---\n/m.match(text)
  data = match && YAML.safe_load(match[1], permitted_classes: [], permitted_symbols: [], aliases: false)
  name = data.is_a?(Hash) && data['name']
  description = data.is_a?(Hash) && data['description']
  valid = data.is_a?(Hash) && (data.keys - %w[name description license allowed-tools metadata]).empty? && name.is_a?(String) && name.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/) && name.length <= 64 && name == File.basename(File.dirname(path)) && description.is_a?(String) && !description.empty? && description.length <= 1024 && !description.match?(/[<>]/) && !text.include?('[TODO:')
  failures << path unless valid
end
puts "#{files.length - failures.length}/#{files.length} skills: safe YAML, names, descriptions, fields and placeholders valid"
puts failures
exit(failures.empty? ? 0 : 1)
CUCKODING_SKILLS
```

The reference/deletion checker used this exact command (the /tmp baseline belongs
to this reset session; future runs can validate references without that comparison):

```sh
rtk proxy python3 - <<'CUCKODING_CHECK'
from pathlib import Path
import re, subprocess, json
root = Path.cwd()
files = [Path("README.md"), Path("AGENTS.md"), *Path("docs").rglob("*.md"), *Path(".agents").rglob("SKILL.md"), *Path(".cuckoding").rglob("*.md"), *Path(".cursor").rglob("*.mdc"), *Path("tasks").rglob("*.md"), *Path("worklog").rglob("*.md")]
errors = []
links = 0
for path in files:
    content = path.read_text()
    if content.count("\x60\x60\x60") % 2:
        errors.append(f"{path}: unclosed code fence")
    for dest in re.findall(r"(?<!!)\[[^\]]+\]\(([^)]+)\)", content):
        if re.match(r"\w+://|mailto:", dest):
            continue
        target, _, anchor = dest.partition("#")
        resolved = path.parent / target if target else path
        if not resolved.exists():
            errors.append(f"{path}: missing link {dest}")
        elif anchor and resolved.is_file():
            headings = re.findall(r"^#{1,6}\s+(.+)$", resolved.read_text(), re.M)
            anchors = {re.sub(r"[^\w\- ]", "", h.lower()).replace(" ", "-") for h in headings}
            if anchor not in anchors:
                errors.append(f"{path}: missing anchor {dest}")
        links += 1
    for ref in re.findall(r"\x60(docs/[^\x60]+\.md)\x60", content):
        if not (root / ref).is_file():
            errors.append(f"{path}: missing contract {ref}")
baseline = json.loads(Path("/tmp/cuckoding-r001-baseline.json").read_text())
tracked = subprocess.check_output(["rtk", "proxy", "git", "ls-files", "-z"]).decode().split("\0")
initial_missing = [p for p in tracked if p and p not in baseline["all_existing_paths"]]
restored = [p for p in initial_missing if Path(p).exists()]
if len(initial_missing) != 700 or restored:
    errors.append(f"Deletion preservation failed: initial={len(initial_missing)}, restored={restored}")
plan = Path("docs/PLAN.md").read_text()
if "- [x]" in plan.lower():
    errors.append("Implementation plan claims completed work")
print(f"Checked {len(files)} text files, {links} local links, contract paths and code fences")
print(f"Preserved {len(initial_missing)} initial deletions; no restored implementation files")
print("Implementation checklist: all pending")
print("\n".join(errors) if errors else "PASS")
raise SystemExit(bool(errors))
CUCKODING_CHECK
```

Additional review command:

```sh
rtk proxy rg -n -i 'xerj|agentdesk|reviewer|spec.writer|implementer|start board|start project|implemented|passed|beta' README.md AGENTS.md docs .agents .cuckoding .cursor
rtk git diff --numstat -- README.md AGENTS.md docs .agents .cursor .cuckoding .github
rtk git diff --check
```

Search hits were inspected: legacy workflow/provider claims remain only as
historical descriptions or future verification requirements. A remaining
“Reviewer attempt” field label was corrected to “Secutor attempt.”

## Handoff

Begin **R010** from [PLAN](../docs/PLAN.md). Do not restore the deleted application
wholesale or treat this documentation as implemented software. Ten-minute setup,
provider compatibility, physical sleep, parallel integration and signed packaging
remain explicit implementation/release gates. Original app data, installed
tools, running applications and remote publication were untouched.
