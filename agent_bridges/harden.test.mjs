import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, mkdirSync, writeFileSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { runInNewContext } from "node:vm";
import { harden } from "./harden.mjs";

const source = (pkg, file) => readFileSync(new URL(`./node_modules/@agentclientprotocol/${pkg}/dist/${file}`, import.meta.url), "utf8");

test("Codex presets cannot widen the saved grant or fall back to a bundled runtime", () => {
  const input = source("codex-acp", "index.js");
  assert.throws(() => harden("codex/index.js", input + "\n"), /Unreviewed/);
  const patched = harden("codex/index.js", input);
  assert.ok(patched.includes("outputSchema: JSON.parse(fs.readFileSync(process.env.CUCKODING_CODEX_OUTPUT_SCHEMA_FILE, 'utf8'))"));
  assert.ok(patched.includes('fs.readFileSync(process.env["CUCKODING_CODEX_CONFIG_FILE"], "utf8")'));
  const env = { INITIAL_AGENT_MODE: "read-only", CUCKODING_CODEX_ARGS: '["app-server","--strict-config"]' };
  const modeSource = patched.slice(patched.indexOf("var MODE_CONFIG_ID"), patched.indexOf("// src/CodexAcpClient.ts"));
  const Mode = runInNewContext(modeSource + "\nAgentMode;", { process: { env } });
  assert.deepEqual(JSON.parse(JSON.stringify(Mode.all().map(m => m.id))), ["read-only", "workspace-write"]);
  assert.equal(Mode.ReadOnly.sandboxPolicy.type, "readOnly");
  assert.equal(Mode.Agent.sandboxPolicy.excludeTmpdirEnvVar, true);
  assert.equal(Mode.Agent.sandboxPolicy.excludeSlashTmp, true);
  assert.equal(Mode.Agent.sandboxPolicy.networkAccess, false);
  assert.ok(Mode.all().every(m => m.approvalPolicy === "never" && m.approvalsReviewer === "user"));
  env.INITIAL_AGENT_MODE = "agent-full-access";
  assert.throws(() => Mode.getInitialAgentMode(), /Invalid Cuckoding mode/);
  const launch = patched.slice(patched.indexOf("function startCodexConnection("), patched.indexOf("  attachLogs(codex);"));
  const calls = [];
  const start = runInNewContext(launch + "return codex; }\nstartCodexConnection;", {
    process: { env, platform: "darwin" }, spawn: (...args) => calls.push(args),
  });
  assert.throws(() => start(undefined), /Explicit supported/);
  start("/app-owned/codex");
  assert.equal(calls[0][0], "/app-owned/codex");
  assert.deepEqual(JSON.parse(JSON.stringify(calls[0][1])), ["app-server", "--strict-config"]);
  assert.equal(calls[0][2].shell, undefined);
});

test("Claude preserves a native structured result as a separate public message", async () => {
  const patched = harden("claude/acp-agent.js", source("claude-agent-acp", "acp-agent.js"));
  assert.ok(!patched.includes("creationOpts.permissionMode ?? settingsManager.getSettings().permissions?.defaultMode"));
  const branch = patched.slice(patched.indexOf("                                    // Retain the native schema-validated result"), patched.indexOf("                                    // The result text is forwarded in two cases."));
  const messages = [];
  await runInNewContext(`(async () => { switch ("success") { case "success": ${branch} } })()`, {
    params: { sessionId: "owned-session" }, message: { structured_output: { summary: "done" } },
    sendUpdate: async update => messages.push(JSON.parse(JSON.stringify(update))),
  });
  assert.equal(messages.length, 1);
  assert.equal(messages[0].sessionId, "owned-session");
  assert.equal(messages[0].update.messageId, "cuckoding-structured-output");
  assert.deepEqual(JSON.parse(messages[0].update.content.text), { summary: "done" });
});

test("Claude reads one fixed run snapshot, refuses unsafe files/modes, and never imports other settings", async () => {
  const root = mkdtempSync(join(tmpdir(), "cuckoding-bridge-settings-"));
  const previous = process.env.CLAUDE_CONFIG_DIR;
  try {
    const profile = join(root, "profile");
    const worktree = join(root, "worktree");
    mkdirSync(profile); mkdirSync(join(worktree, ".claude"), { recursive: true });
    writeFileSync(join(worktree, ".claude/settings.json"), '{"permissions":{"defaultMode":"bypassPermissions"}}');
    process.env.CLAUDE_CONFIG_DIR = profile;
    const code = harden("claude/settings.js", source("claude-agent-acp", "settings.js"));
    const { SettingsManager } = await import("data:text/javascript;base64," + Buffer.from(code).toString("base64"));
    const manager = new SettingsManager(worktree);
    await assert.rejects(manager.initialize(), /ENOENT/);
    const settings = join(profile, "settings.json");
    writeFileSync(settings, '{"permissions":{"defaultMode":"dontAsk"}}');
    await manager.initialize();
    assert.equal(manager.getSettings().permissions.defaultMode, "dontAsk");
    writeFileSync(settings, '{"permissions":{"defaultMode":"bypassPermissions"}}');
    assert.equal(manager.getSettings().permissions.defaultMode, "dontAsk");
    await assert.rejects(manager.initialize(), /Unsupported/);
    await assert.rejects(manager.setCwd(root), /cannot change/);
    rmSync(settings); symlinkSync(join(worktree, ".claude/settings.json"), settings);
    await assert.rejects(manager.initialize(), /Invalid Claude settings/);
    const modes = harden("claude/session-mode.js", source("claude-agent-acp", "session-mode.js"));
    const Manager = runInNewContext(modes.slice(modes.indexOf("export class")).replace("export class", "class") + "\nSessionModeManager;");
    assert.deepEqual(JSON.parse(JSON.stringify(new Manager({}).buildAvailableModes(true).map(m => m.id))), ["dontAsk", "plan"]);
    const entry = harden("claude/index.js", source("claude-agent-acp", "index.js"));
    assert.ok(!entry.includes("await applyManagedPolicyEnv()"));
  } finally {
    if (previous === undefined) delete process.env.CLAUDE_CONFIG_DIR;
    else process.env.CLAUDE_CONFIG_DIR = previous;
    rmSync(root, { recursive: true, force: true });
  }
});
