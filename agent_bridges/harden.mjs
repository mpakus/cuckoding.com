// Apache-2.0 upstream packages, pinned in package-lock.json. These patches only
// narrow execution policy. Refuse drift instead of applying approximate edits.
import { createHash } from "node:crypto";

export const versions = { codex: "1.13.1+cuckoding.1", claude: "0.81.2+cuckoding.1" };

const hashes = {
  "codex/index.js": "4c1f6c00e67c2ace5a96f0e0fe6e812502a48827a403014d4b68373464f55fce",
  "claude/index.js": "ecfa6ff948a4241090934979179a5ba035bb0a7c3ef543752f4a304d44a267fb",
  "claude/settings.js": "629348525ddd007ace9c06a16a19af6877af2a090b58255dd7f5974a6bdf2932",
  "claude/session-mode.js": "12190554cf1aab0733dc808ec6254a6e18ea8fff77d976760d995aec7cb680d1",
  "claude/acp-agent.js": "36a33a984624541ea013c085f5bd1d982294cfe70beb42826752f62bdc538d64",
};

function replaceOnce(source, before, after) {
  if (source.split(before).length !== 2) throw new Error("Bridge patch does not match exactly once");
  return source.replace(before, after);
}

export function harden(name, source) {
  if (createHash("sha256").update(source).digest("hex") !== hashes[name]) {
    throw new Error(`Unreviewed bridge source: ${name}`);
  }
  if (name === "codex/index.js") return hardenCodex(source);
  if (name === "claude/settings.js") return claudeSettings;
  if (name === "claude/acp-agent.js") {
    source = replaceOnce(source,
      "creationOpts.permissionMode ?? settingsManager.getSettings().permissions?.defaultMode",
      "settingsManager.getSettings().permissions.defaultMode");
    return replaceOnce(source,
      "                                    // The result text is forwarded in two cases.",
      `                                    // Retain the native schema-validated result as a separate ACP message.
                                    if (message.structured_output !== undefined) {
                                        await sendUpdate({ sessionId: params.sessionId, update: {
                                            sessionUpdate: "agent_message_chunk",
                                            messageId: "cuckoding-structured-output",
                                            content: { type: "text", text: JSON.stringify(message.structured_output) }
                                        }});
                                        break;
                                    }
                                    // The result text is forwarded in two cases.`);
  }
  if (name === "claude/index.js") {
    return replaceOnce(source, "await applyManagedPolicyEnv();", "// Native Claude still enforces managed policy; the bridge cannot import environment grants.");
  }
  return replaceOnce(source,
    source.slice(source.indexOf("    buildAvailableModes(allowBypass) {"), source.indexOf("    async trySyncMode(")),
    `    buildAvailableModes() {
        return [
            { id: "dontAsk", name: "Granted tools only", description: "Deny tools outside the saved grant" },
            { id: "plan", name: "Plan", description: "Read-only planning" },
        ];
    }
`);
}

function hardenCodex(source) {
  source = replaceOnce(source,
    source.slice(source.indexOf("  static ReadOnly = new _AgentMode("), source.indexOf("  toSessionMode() {", source.indexOf("// src/AgentMode.ts"))),
    `  static ReadOnly = new _AgentMode(
    "read-only", "Read only", "Cuckoding read-only grant", "standard", "never", "user",
    { type: "readOnly" }, "read-only"
  );
  static Agent = new _AgentMode(
    "workspace-write", "Workspace write", "Cuckoding worktree grant", "standard", "never", "user",
    { type: "workspaceWrite", writableRoots: [], networkAccess: false,
      excludeTmpdirEnvVar: true, excludeSlashTmp: true }, "workspace-write"
  );
  static DEFAULT_AGENT_MODE = _AgentMode.ReadOnly;
`);
  source = replaceOnce(source,
    "return [_AgentMode.ReadOnly, _AgentMode.Agent, _AgentMode.AgentFullAccess];",
    "return [_AgentMode.ReadOnly, _AgentMode.Agent];");
  source = replaceOnce(source,
    "return _AgentMode.find(predefinedAgentMode) ?? _AgentMode.DEFAULT_AGENT_MODE;",
    "const mode = _AgentMode.find(predefinedAgentMode); if (!mode) throw new Error('Invalid Cuckoding mode'); return mode;");
  source = replaceOnce(source,
    "      input: input2,\n      approvalPolicy: agentMode.approvalPolicy,",
    "      input: input2,\n      outputSchema: JSON.parse(fs.readFileSync(process.env.CUCKODING_CODEX_OUTPUT_SCHEMA_FILE, 'utf8')),\n      approvalPolicy: agentMode.approvalPolicy,");
  source = replaceOnce(source,
    'const configString = process.env["CODEX_CONFIG"];',
    'const configString = fs.readFileSync(process.env["CUCKODING_CODEX_CONFIG_FILE"], "utf8");');
  source = replaceOnce(source,
    source.slice(source.indexOf("  if (codexPath) {", source.indexOf("function startCodexConnection(")), source.indexOf("  attachLogs(codex);", source.indexOf("function startCodexConnection("))),
    `  if (!codexPath || process.platform === "win32") throw new Error("Explicit supported Codex executable required");
  const args = JSON.parse(process.env.CUCKODING_CODEX_ARGS);
  if (!Array.isArray(args) || !args.every(arg => typeof arg === "string")) throw new Error("Invalid Codex arguments");
  codex = spawn(codexPath, args, { env: spawnEnv });
`);
  return replaceOnce(source, 'version: "1.13.1",', `version: "${versions.codex}",`);
}

// The run's generated settings are an immutable snapshot. No project, personal,
// or managed environment is imported by the bridge. Native policy still applies.
const claudeSettings = `import { lstatSync, readFileSync } from "node:fs";
import { isAbsolute, join } from "node:path";
export class SettingsManager {
  constructor(cwd) { this.cwd = cwd; }
  async initialize() {
    const root = process.env.CLAUDE_CONFIG_DIR;
    if (!root || !isAbsolute(root)) throw new Error("Run-owned Claude settings required");
    const file = join(root, "settings.json");
    const stat = lstatSync(file);
    if (!stat.isFile() || stat.size > 1048576) throw new Error("Invalid Claude settings file");
    this.effective = JSON.parse(readFileSync(file, "utf8"));
    if (!["plan", "dontAsk"].includes(this.effective?.permissions?.defaultMode))
      throw new Error("Unsupported Claude permission mode");
  }
  getSettings() { return this.effective; }
  getCwd() { return this.cwd; }
  async setCwd(cwd) { if (cwd !== this.cwd) throw new Error("Session worktree cannot change"); }
  dispose() {}
}
`;
