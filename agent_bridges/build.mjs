import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { harden, versions } from "./harden.mjs";

const root = dirname(fileURLToPath(import.meta.url));
const output = join(root, "../priv/agent_bridges");
const bun = process.env.BUN_BIN || "bun";
if (execFileSync(bun, ["--version"], { encoding: "utf8" }).trim() !== "1.3.10") {
  throw new Error("Bridge builds require Bun 1.3.10");
}
if (process.platform !== "darwin" || !["arm64", "x64"].includes(process.arch)) {
  throw new Error("Bridge packaging currently supports macOS arm64/x64 only");
}
const temporary = mkdtempSync(join(root, ".build-"));
const manifest = { schema: 1, platform: process.platform, arch: process.arch, bun: "1.3.10", bridges: {} };
try {
  mkdirSync(output, { recursive: true });
  for (const [name, pkg] of Object.entries({ codex: "codex-acp", claude: "claude-agent-acp" })) {
    const upstream = join(root, "node_modules/@agentclientprotocol", pkg);
    const working = join(temporary, name);
    cpSync(upstream, working, { recursive: true });
    const files = name === "codex" ? ["index.js"] : ["index.js", "settings.js", "session-mode.js", "acp-agent.js"];
    for (const file of files) {
      const path = join(working, "dist", file);
      writeFileSync(path, harden(`${name}/${file}`, readFileSync(path, "utf8")));
    }
    const pkgPath = join(working, "package.json");
    const metadata = JSON.parse(readFileSync(pkgPath, "utf8"));
    if (metadata.version !== versions[name].split("+")[0] || metadata.license !== "Apache-2.0") {
      throw new Error("Unreviewed bridge metadata");
    }
    writeFileSync(pkgPath, JSON.stringify({ ...metadata, version: versions[name] }));
    const executable = `${name}-acp`;
    const binary = join(temporary, executable);
    execFileSync(bun, ["build", join(working, "dist/index.js"), "--compile", "--minify",
      "--no-env-file", "--config=/dev/null", "--env=disable",
      "--no-compile-autoload-dotenv", "--no-compile-autoload-bunfig",
      "--no-compile-autoload-tsconfig", "--no-compile-autoload-package-json",
      "--outfile", binary], { stdio: "inherit", cwd: root });
    // Probe the shipped artifact in a hostile repository, without build-machine credentials.
    const probe = join(temporary, `${name}-probe`);
    mkdirSync(probe);
    writeFileSync(join(probe, ".env"), `APP_SERVER_LOGS=${join(probe, "unexpected-env")}\n`);
    writeFileSync(join(probe, "bunfig.toml"), 'preload = ["./preload.js"]\n');
    writeFileSync(join(probe, "preload.js"), 'require("node:fs").writeFileSync("unexpected-preload", "canary");');
    const banner = execFileSync(binary, ["--version"], {
      encoding: "utf8", timeout: 15000, cwd: probe,
      env: { PATH: "/usr/bin:/bin:/usr/sbin:/sbin", HOME: probe }
    }).trim();
    if (existsSync(join(probe, "unexpected-env")) || existsSync(join(probe, "unexpected-preload"))) {
      throw new Error("Compiled bridge loaded repository configuration");
    }
    const expected = name === "codex" ? `${metadata.name} ${versions[name]}` : versions[name];
    if (banner !== expected) throw new Error("Compiled bridge version mismatch");
    const version = versions[name];
    const sha256 = createHash("sha256").update(readFileSync(binary)).digest("hex");
    renameSync(binary, join(output, executable));
    cpSync(join(upstream, "LICENSE"), join(output, `${name}-LICENSE`));
    manifest.bridges[name] = { executable, version, sha256, package: metadata.name, license: metadata.license };
  }
  const notices = ["Cuckoding ACP bridges: modified 2026-09-27. See agent_bridges/harden.mjs for policy and structured-output patches.\n"];
  const lock = JSON.parse(readFileSync(join(root, "package-lock.json"), "utf8"));
  for (const [path, metadata] of Object.entries(lock.packages)) {
    const directory = join(root, path);
    if (!path || !existsSync(directory)) continue;
    notices.push(`\n--- ${path} ${metadata.version} (${metadata.license || "see package notice"}) ---\n`);
    const files = readdirSync(directory).filter(file => /^(licen[sc]e|copying|notice)(\.|$)/i.test(file));
    if (!files.length && existsSync(join(directory, "README.md"))) files.push("README.md");
    for (const file of files) notices.push(readFileSync(join(directory, file), "utf8"));
  }
  writeFileSync(join(output, "THIRD-PARTY-NOTICES.txt"), notices.join("\n"));
  cpSync(join(root, "BUN-LICENSE.md"), join(output, "BUN-LICENSE.md"));
  const buildSource = join(output, "build-source");
  mkdirSync(buildSource, { recursive: true });
  for (const file of ["package.json", "package-lock.json", "build.mjs", "harden.mjs", "harden.test.mjs", "README.md", "BUN-LICENSE.md"]) {
    cpSync(join(root, file), join(buildSource, file));
  }
  writeFileSync(join(temporary, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
  renameSync(join(temporary, "manifest.json"), join(output, "manifest.json"));
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
