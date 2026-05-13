// Approval hook for risky tool calls.
//
// Uses OMP's configured smol model (from ~/.omp/agent/config.yml modelRoles.smol)
// via raw fetch to the OpenAI-compatible /chat/completions endpoint. The model's
// baseUrl and API key are resolved through ctx.modelRegistry.
//
// Classification is tried in order:
//   1. Primary smol model (from config.yml modelRoles.smol)
//   2. Fallback chain (from config.yml retry.fallbackChains.smol)
//   3. Local regex classifier (ultimate fallback — no network needed)
//
// Three modes: normal (prompt+whitelist), edits (auto-allow in-repo edits), auto (LLM classifier).
// Switch via: omp-approve-mode normal|edits|auto
//
// State stored per-repo in .claude/settings.local.json using the Claude Code
// settings schema (https://json.schemastore.org/claude-code-settings.json).
// Whitelisted commands become Bash(...) entries in permissions.allow.
// Mode is persisted as permissions.defaultMode.

import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

export default function (pi) {
  // ============================================================
  // Constants
  // ============================================================

  const CLASSIFY_PROMPT = `You are a safety classifier for CLI commands in a NixOS dotfiles repo. Determine if the proposed command is safe to execute automatically (safe) or requires user confirmation (unsafe).

Respond ONLY with a JSON object: { "safe": boolean, "reason": "brief explanation" }

SAFE (automatic, no confirmation needed):
- Reading files and directories (cat, ls, find, grep, head, tail, less, read, stat, file, du, df)
- Operations limited to /tmp or obviously safe temp locations
- Echo, printf, print, and other display commands
- Building without switching (nix build, nix develop, nix shell, cargo build, go build)
- Network fetches (curl, wget) that DO NOT pipe to shell
- Grepping, searching, listing
- Package queries (nix search, apt-cache, pip list)

UNSAFE (requires user confirmation):
- ANY git command (git status, git log, git diff, git add, git commit, git push, git pull, git checkout, etc.) — all git invocations require explicit user confirmation, no exceptions
- Deleting files outside /tmp (rm -rf on /etc, /nix, /boot, /home, /root, /var, /opt, /usr)
- System mutations (nixos-rebuild switch|boot|test, home-manager switch, nix-collect-garbage)
- Force-pushing or rewriting git history (git push --force, git reset --hard)
- Database schema changes (drop table, drop database, alter table, truncate)
- Piping curl/wget directly to shell
- Formatting or partitioning disks (mkfs, dd, fdisk, parted, mkswap)
- Installing/modifying system packages outside /tmp
- Writing to system config paths (/etc, /nix, /boot)

The user runs commands in a NixOS environment with home-manager. Commands touching /nix/store are sensitive. Commands inside /tmp or that just print/output are safe.`;

  const CLASSIFY_TIMEOUT_MS = 10000;
  const VALID_MODES = ["normal", "edits", "auto"];

  const MODE_TO_DEFAULT_MODE: Record<string, string> = {
    normal: "default",
    edits: "acceptEdits",
    auto: "auto",
  };

  const DEFAULT_MODE_TO_MODE: Record<string, string> = {
    default: "normal",
    acceptedits: "edits",
    auto: "auto",
  };

  // ============================================================
  // Repo root (lazy — process may not be available in OMP sandbox)
  // ============================================================

  let _repoRoot: string | null = null;
  function repoRoot(): string {
    if (!_repoRoot) {
      try { _repoRoot = process.cwd(); } catch { _repoRoot = "/"; }
    }
    return _repoRoot;
  }

  // ============================================================
  // State management — .claude/settings.local.json (Claude Code format)
  // ============================================================

  function settingsFilePath(): string {
    return path.join(repoRoot(), ".claude", "settings.local.json");
  }

  function oldStateFilePath(): string {
    const safe = repoRoot().replace(/^\/+/, "").replace(/[\/:]/g, "-") || "root";
    return path.join(os.homedir(), ".omp", "agent", "approve-state", safe + ".json");
  }

  /** Ensure the parent directory exists. */
  function ensureDir(fp: string): void {
    fs.mkdirSync(path.dirname(fp), { recursive: true });
  }

  /**
   * Read the full settings.local.json (Claude Code format).
   * Performs one-time migration from the old ~/.omp/agent/approve-state/ format.
   */
  function loadSettings(): Record<string, unknown> {
    const sfp = settingsFilePath();
    try {
      const raw = fs.readFileSync(sfp, "utf-8");
      return JSON.parse(raw);
    } catch {
      // File doesn't exist or is unparseable — try migration from old state
      return migrateFromOldState();
    }
  }

  /** Migrate old ~/.omp/agent/approve-state/<repo>.json → .claude/settings.local.json */
  function migrateFromOldState(): Record<string, unknown> {
    const oldPath = oldStateFilePath();
    try {
      const raw = fs.readFileSync(oldPath, "utf-8");
      const parsed = JSON.parse(raw);
      const oldMode: string = parsed.mode || "normal";
      const oldWhitelist: Array<{ pattern: string; description: string }> =
        Array.isArray(parsed.whitelist) ? parsed.whitelist : [];

      const allow: string[] = [];
      for (const entry of oldWhitelist) {
        // Convert old regex patterns to Claude Code Bash(...) rules.
        // The old patterns were regexes like "^git\\s+status\\b".
        // We do our best to convert them to glob-style rules.
        const rule = regexToPermissionRule(entry.pattern, entry.description);
        if (rule && !allow.includes(rule)) {
          allow.push(rule);
        }
      }

      const settings: Record<string, unknown> = {
        "$schema": "https://json.schemastore.org/claude-code-settings.json",
        permissions: {
          allow,
          deny: [],
          defaultMode: MODE_TO_DEFAULT_MODE[oldMode] || "default",
        },
      };

      // Write the migrated settings
      const sfp = settingsFilePath();
      ensureDir(sfp);
      fs.writeFileSync(sfp, JSON.stringify(settings, null, 2), "utf-8");

      // Remove the old state file so migration doesn't repeat
      try { fs.unlinkSync(oldPath); } catch { /* ignore */ }

      console.error("[approve] migrated old state to .claude/settings.local.json");
      return settings;
    } catch {
      return {};
    }
  }

  /**
   * Best-effort conversion of an old regex pattern to a Claude Code permission rule.
   * The old format used anchored regexes like "^git\\s+status\\b".
   */
  function regexToPermissionRule(pattern: string, description: string): string | null {
    // Try to extract a command prefix from the description first (most reliable)
    if (description && description.endsWith(" *")) {
      const base = description.slice(0, -2); // strip trailing " *"
      return "Bash(" + base.trim() + " *)";
    }

    // Try to extract from the regex pattern
    // Remove ^ anchor
    let p = pattern.replace(/^\\?\^/, "");
    // Replace \\s+ with a single space
    p = p.replace(/\\s\+/g, " ");
    // Remove \\b word boundaries
    p = p.replace(/\\b/g, "");
    // Remove $ anchor
    p = p.replace(/\\?\$/, "");

    if (!p || p === ".*") return null;

    // If it's a simple command prefix, generate a Bash rule
    if (/^[a-zA-Z0-9_./-]+(?:\s+[a-zA-Z0-9_./*-]+)?$/.test(p)) {
      return "Bash(" + p + " *)";
    }

    return null;
  }

  function saveSettings(settings: Record<string, unknown>): void {
    try {
      const sfp = settingsFilePath();
      ensureDir(sfp);
      fs.writeFileSync(sfp, JSON.stringify(settings, null, 2), "utf-8");
    } catch (err: any) {
      console.error("[approve] failed to save settings:", err?.message || err);
    }
  }

  /** Ensure the permissions object exists in settings. */
  function ensurePermissions(settings: Record<string, unknown>): Record<string, unknown> {
    if (!settings.permissions || typeof settings.permissions !== "object") {
      settings.permissions = { allow: [], deny: [], defaultMode: "default" };
    }
    const perms = settings.permissions as Record<string, unknown>;
    if (!Array.isArray(perms.allow)) perms.allow = [];
    if (!Array.isArray(perms.deny)) perms.deny = [];
    if (!perms.defaultMode) perms.defaultMode = "default";
    return perms;
  }

  // ---- Mode (stored as permissions.defaultMode) ----

  function getMode(): string {
    try {
      const envMode = process.env?.OMP_APPROVE_MODE || "";
      if (VALID_MODES.includes(envMode)) return envMode;
    } catch { /* process unavailable */ }
    const settings = loadSettings();
    const perms = settings.permissions as Record<string, unknown> | undefined;
    if (perms?.defaultMode && typeof perms.defaultMode === "string") {
      return DEFAULT_MODE_TO_MODE[perms.defaultMode.toLowerCase()] || "normal";
    }
    return "normal";
  }

  function setMode(mode: string): void {
    const settings = loadSettings();
    const perms = ensurePermissions(settings);
    perms.defaultMode = MODE_TO_DEFAULT_MODE[mode] || "default";
    saveSettings(settings);
  }

  // ---- Bash permission rule matching ----

  /**
   * Split a compound command on shell operators.
   * Claude Code splits on: &&, ||, ;, |, |&, &, newline
   * Each subcommand must independently match a permission rule.
   */
  function splitCompoundCommands(cmd: string): string[] {
    // Simple split on common shell operators. This is a best-effort
    // approximation of Claude Code's AST-aware parser.
    return cmd
      .split(/\s*(?:&&|\|\||[;&|])\s*/)
      .map(s => s.trim())
      .filter(Boolean);
  }

  /**
   * Strip process wrappers Claude Code ignores before matching.
   * Recognized: timeout, time, nice, nohup, stdbuf, bare xargs.
   */
  function stripWrappers(cmd: string): string {
    let result = cmd.trim();
    for (let i = 0; i < 5; i++) {
      const prev = result;
      result = result.replace(/^timeout\s+(?:\S+\s+)?/, "");
      result = result.replace(/^time\s+/, "");
      result = result.replace(/^nice\s+(?:-n\s+\S+\s+)?/, "");
      result = result.replace(/^nohup\s+/, "");
      result = result.replace(/^stdbuf\s+(?:-[ioe]\S+\s+)+/, "");
      result = result.replace(/^xargs\s+/, ""); // bare xargs only
      if (result === prev) break;
    }
    return result.trim();
  }

  /**
   * Convert a Claude Code Bash permission glob to a RegExp.
   * `*` matches any sequence of characters including spaces.
   * Patterns are implicitly anchored.
   */
  function globToRegex(glob: string): RegExp {
    // Escape regex specials except *
    let escaped = glob.replace(/[.+^${}()|[\]\\]/g, "\\$&");
    // Replace * with .* (greedy, spans spaces)
    escaped = escaped.replace(/\*/g, ".*");
    return new RegExp("^" + escaped + "$");
  }

  /**
   * Test whether a Bash permission rule matches a command.
   * Rule format: "Bash(<glob>)" where glob uses * wildcards.
   *
   * Compound commands (&&, ||, ;, |, |&, &) are split — every
   * subcommand must independently match.
   *
   * Process wrappers (timeout, time, nice, nohup, stdbuf, bare xargs)
   * are stripped before matching.
   */
  function bashRuleMatches(rule: string, cmd: string, matchAnySub = false): boolean {
    if (!rule.startsWith("Bash(") || !rule.endsWith(")")) return false;
    const glob = rule.slice(5, -1);

    if (glob === "*" || glob === "") return true;

    const subcommands = splitCompoundCommands(cmd);
    if (subcommands.length === 0) return false;

    const regex = globToRegex(glob);
    const test = (sub: string) => regex.test(stripWrappers(sub));
    return matchAnySub ? subcommands.some(test) : subcommands.every(test);
  }

  // ============================================================
  // Path permission matching — Read(), Edit(), Write() rules
  // ============================================================

  /**
   * Convert a gitignore-style glob to a RegExp.
   * * matches within one directory (no slash); ** matches recursively.
   * Pattern is anchored at the resolved base path.
   */
  function gitignoreToRegex(glob: string): RegExp {
    let out = "";
    let i = 0;
    while (i < glob.length) {
      if (glob[i] === "*" && glob[i + 1] === "*") {
        // ** matches anything including slashes
        out += ".*";
        i += 2;
        // Skip trailing slash after ** (e.g., **/foo → .*/foo)
        if (glob[i] === "/") i++;
      } else if (glob[i] === "*") {
        // * matches anything except /
        out += "[^/]*";
        i++;
      } else if (glob[i] === "?") {
        out += "[^/]";
        i++;
      } else {
        // Escape regex specials
        if (/[.+^${}()|[\]\\]/.test(glob[i])) out += "\\";
        out += glob[i];
        i++;
      }
    }
    return new RegExp("^" + out + "$");
  }

  /**
   * Resolve a Claude Code permission rule path to an absolute path.
   *  //path → absolute filesystem path
   *  ~/path → home directory
   *  /path  → relative to project root
   *  path or ./path → relative to current directory (repo root)
   */
  function resolvePermissionPath(rulePath: string): string {
    if (rulePath.startsWith("//")) {
      return path.resolve(rulePath.slice(1)); // //Users/... → /Users/...
    }
    if (rulePath.startsWith("~/")) {
      return path.join(os.homedir(), rulePath.slice(2));
    }
    if (rulePath.startsWith("/")) {
      return path.join(repoRoot(), rulePath.slice(1));
    }
    if (rulePath.startsWith("./")) {
      return path.join(repoRoot(), rulePath.slice(2));
    }
    return path.join(repoRoot(), rulePath);
  }

  /**
   * Test whether a file path matches a Read()/Edit()/Write() permission rule.
   * Splits the rule path into a literal prefix and a gitignore glob suffix,
   * resolves the prefix against the rule anchor (// ~/ / ./), then matches
   * the relative remainder with gitignore semantics.
   */
  function pathRuleMatches(rule: string, filePath: string): boolean {
    const m = rule.match(/^(Read|Edit|Write)\((.+)\)$/);
    if (!m) return false;
    const raw = m[2];

    // Split into literal prefix (before first glob char) and glob suffix
    const globIdx = raw.search(/[*?[]/);
    const literal = globIdx === -1 ? raw : raw.slice(0, globIdx);
    const glob = globIdx === -1 ? "" : raw.slice(globIdx);

    // Resolve the literal prefix to an absolute directory
    let base: string;
    if (literal.startsWith("//")) {
      base = path.resolve(literal.slice(1));
    } else if (literal.startsWith("~/")) {
      base = path.join(os.homedir(), literal.slice(2));
    } else if (literal.startsWith("/")) {
      base = path.join(repoRoot(), literal.slice(1));
    } else if (literal.startsWith("./")) {
      base = path.join(repoRoot(), literal.slice(2));
    } else {
      base = path.join(repoRoot(), literal);
    }
    // Remove trailing / so path.relative works clean
    base = base.replace(/\/+$/, "") || "/";

    // Resolve the target file path
    let resolvedFile = filePath;
    if (!path.isAbsolute(resolvedFile)) {
      resolvedFile = path.resolve(repoRoot(), resolvedFile);
    }
    // Bare filename (no /, no glob, no anchor) → matches at any depth
    // Gitignore semantics: Read(.env) ≡ Read(**/.env)
    if (!glob && !raw.includes("/") &&
        !raw.startsWith("//") && !raw.startsWith("~/") &&
        !raw.startsWith("/") && !raw.startsWith("./")) {
      // Base for bare filenames is the enclosing directory (repo root)
      const bareBase = path.join(repoRoot());
      if (!resolvedFile.startsWith(bareBase + path.sep) && resolvedFile !== bareBase) return false;
      return path.basename(resolvedFile) === raw;
    }
    // No glob → exact path match
    if (!glob) {
      return resolvedFile === base;
    }

    // Get file path relative to the resolved base
    const relative = path.relative(base, resolvedFile);
    if (relative.startsWith("..")) return false; // file is above the base

    // Match gitignore glob against the relative path
    // Prepend any trailing separator from the literal for correct anchoring
    const matchGlob = (literal.endsWith("/") ? "" : "") + glob;
    return gitignoreToRegex(matchGlob).test(relative);
  }

  /**
   * Check file access permissions (Read/Edit/Write rules) against a file path.
   * Returns: true if allowed, false if denied or no matching rule.
   */
  function checkFilePermission(filePath: string): boolean {
    const settings = loadSettings();
    const perms = settings.permissions as Record<string, unknown> | undefined;
    const allow: string[] = Array.isArray(perms?.allow) ? perms.allow as string[] : [];
    const deny: string[] = Array.isArray(perms?.deny) ? perms.deny as string[] : [];

    // Deny takes precedence
    for (const rule of deny) {
      if (pathRuleMatches(rule, filePath)) return false;
    }

    for (const rule of allow) {
      if (pathRuleMatches(rule, filePath)) return true;
    }

    // No matching rule → not pre-authorized
    return false;
  }

  // ---- Whitelist (permissions.allow) ----

  function checkWhitelist(cmd: string): boolean {
    const settings = loadSettings();
    const perms = settings.permissions as Record<string, unknown> | undefined;
    const allow: string[] = Array.isArray(perms?.allow) ? perms.allow as string[] : [];
    const deny: string[] = Array.isArray(perms?.deny) ? perms.deny as string[] : [];
    const trimmed = cmd.trim();

    // Deny takes precedence (Claude Code semantics: deny → ask → allow)
    for (const rule of deny) {
      if (bashRuleMatches(rule, trimmed, true)) return false;
    }

    for (const rule of allow) {
      if (bashRuleMatches(rule, trimmed)) return true;
    }
    return false;
  }

  function addToWhitelist(rule: string): void {
    const settings = loadSettings();
    const perms = ensurePermissions(settings);
    const allow = perms.allow as string[];
    if (!allow.includes(rule)) {
      allow.push(rule);
      saveSettings(settings);
      console.error("[approve] added permission:", rule);
    }
  }

  // ============================================================
  // Permission rule generation for whitelist suggestions
  // ============================================================

  function generatePermissionRule(cmd: string): { rule: string; description: string } {
    const trimmed = cmd.trim();
    const words = trimmed.split(/\s+/);
    // Single-word command → exact match (Bash(lsof) not Bash(lsof *))
    if (words.length <= 1) {
      return { rule: "Bash(" + trimmed + ")", description: trimmed };
    }
    const base = extractCommandBase(trimmed);
    const rule = "Bash(" + base + " *)";
    return { rule, description: base + " *" };
  }

  function extractCommandBase(cmd: string): string {
    const words = cmd.split(/\s+/);
    if (words.length === 0) return cmd;

    // git <subcommand> — "git status"
    if (words[0] === "git" && words.length >= 2) {
      return words.slice(0, 2).join(" ");
    }
    // nix <subcommand> — "nix build"
    if (words[0] === "nix" && words.length >= 2) {
      return words.slice(0, 2).join(" ");
    }
    // systemctl <action> — "systemctl status"
    if (words[0] === "systemctl" && words.length >= 2) {
      return words.slice(0, 2).join(" ");
    }
    // kubectl <action> — "kubectl get"
    if (words[0] === "kubectl" && words.length >= 2) {
      return words.slice(0, 2).join(" ");
    }
    // Default: just first word
    return words[0];
  }

  // ============================================================
  // Config reading helpers
  // ============================================================

  function readSmolModelSpec(): string | null {
    try {
      const cfg = path.join(os.homedir(), ".omp", "agent", "config.yml");
      const raw = fs.readFileSync(cfg, "utf-8");
      const m = raw.match(/^\s*smol:\s*(.+)$/m);
      return m ? m[1].trim() : null;
    } catch {
      return null;
    }
  }

  function readFallbackChain(): string[] {
    try {
      const cfg = path.join(os.homedir(), ".omp", "agent", "config.yml");
      const raw = fs.readFileSync(cfg, "utf-8");
      const fbMatch = raw.match(/fallbackChains:[\s\S]*?smol:([\s\S]*?)(?=\n  \w|\n\w|$)/);
      if (!fbMatch) return [];
      const items = fbMatch[1].matchAll(/- "([^"]+)"/g);
      return [...items].map(m => m[1]);
    } catch {
      return [];
    }
  }

  // ============================================================
  // LLM verdict parsing
  // ============================================================

  function parseVerdictText(text: string): { safe: boolean; reason: string } | null {
    if (!text) return null;
    text = text.replace(/^```(?:json)?\s*\n?/i, "").replace(/\n?```\s*$/i, "");
    try {
      const parsed = JSON.parse(text);
      if (typeof parsed?.safe !== "boolean") return null;
      return { safe: parsed.safe, reason: String(parsed.reason ?? "") };
    } catch {
      return null;
    }
  }

  // ============================================================
  // Local regex classifier (no LLM needed)
  // ============================================================

  function localClassify(cmd: string): { safe: boolean; reason: string; definite: boolean } {
    const trimmed = cmd.trim();

    const unsafePatterns: Array<[RegExp, string]> = [
      [/^git\s+(add|commit|push|pull|checkout|merge|rebase|reset|clean|tag\s+(?!(-l|--list))|stash\s+(push|drop|pop|apply|save)|branch\s+(-d|-D|--delete|--move|-m|--force))\b/, "git mutation"],
      [/\bgit\s+push\s+.*(--force|-f|--delete)\b/, "git force push or branch delete"],
      [/\bnixos-rebuild\s+(switch|boot|test)\b/, "nixos-rebuild system mutation"],
      [/\bhome-manager\s+switch\b/, "home-manager switch"],
      [/\bnix-collect-garbage\b/, "nix-collect-garbage"],
      [/\brm\s+-r?f?\s+(?!\/tmp\b)\//, "recursive deletion outside /tmp"],
      [/\brm\s+-r?f?\s+\/(etc|nix|boot|home|root|var|opt|usr)\b/, "deletion of system directory"],
      [/\b(curl|wget)\b.*\|\s*(sh|bash|sudo\s+bash)\b/, "pipe network fetch to shell"],
      [/\b(mkfs\.|dd\s+if=|fdisk|parted|mkswap)\b/, "disk/partition manipulation"],
      [/\b(drop\s+(table|database)|alter\s+table|truncate(\s+table)?)\b/i, "database schema change"],
      [/\b(nix\s+profile\s+install|apt(-get)?\s+install|pip\d?\s+install)\b/, "package installation"],
      [/[>|]\s*\/+(etc|nix|boot)\//, "writing to system config path"],
    ];

    for (const [pat, reason] of unsafePatterns) {
      if (pat.test(trimmed)) {
        return { safe: false, reason: "local: UNSAFE — " + reason, definite: true };
      }
    }

    const safePatterns: Array<[RegExp, string]> = [
      [/^git\s+(status\b|log\b|diff\b|show\b|stash\s+list\b|branch(?:\s|$)|remote\b|grep\b|blame\b|ls-files\b|ls-tree\b|rev-parse\b|rev-list\b|describe\b|tag(?:\s+(-l|--list)|$))/, "git read-only"],
      [/^(cat|ls|find|grep|head|tail|less|stat|file|du|df)\b/, "file reading"],
      [/^(read|wc|sort|uniq|cut|tr|awk|sed|jq)\b/, "text processing"],
      [/^(echo|printf|print)\b/, "display"],
      [/^(nix\s+(build|develop|shell|search)|cargo\s+build|go\s+build)\b/, "build without switch"],
      [/^(curl|wget)\b/, "network fetch"],
      [/^(which|type|command\s+-v|env|printenv|pwd|whoami|id|uname|hostname|date)\b/, "system info"],
      [/^(apt-cache|pip\d?\s+(list|show|freeze))\b/, "package query"],
      [/^\/tmp\//, "operation in /tmp"],
    ];

    for (const [pat, reason] of safePatterns) {
      if (pat.test(trimmed)) {
        return { safe: true, reason: "local: SAFE — " + reason, definite: true };
      }
    }

    return { safe: false, reason: "local: unrecognized command — blocking by default", definite: false };
  }

  // ============================================================
  // LLM-based classification
  // ============================================================

  async function tryModel(spec: string, cmd: string, modelRegistry: any): Promise<{ safe: boolean; reason: string } | null> {
    const slash = spec.indexOf("/");
    if (slash === -1) { console.error("[approve] invalid model spec:", spec); return null; }

    const provider = spec.slice(0, slash);
    const modelId = spec.slice(slash + 1);
    console.error("[approve] trying model:", provider, modelId);
    const model = modelRegistry.find(provider, modelId);
    if (!model) { console.error("[approve] model not found:", provider, modelId); return null; }

    const apiKey = await modelRegistry.getApiKey(model);
    if (!apiKey) { console.error("[approve] no API key for model:", model.provider, model.id); return null; }

    try {
      const ac = new AbortController();
      const timer = setTimeout(() => ac.abort(), CLASSIFY_TIMEOUT_MS);

      const url = model.baseUrl + "/chat/completions";
      console.error("[approve] fetching:", url);
      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: "Bearer " + apiKey,
        },
        body: JSON.stringify({
          model: model.id,
          messages: [
            { role: "system", content: CLASSIFY_PROMPT },
            { role: "user", content: "Evaluate this command: " + cmd },
          ],
          temperature: 0.1,
          max_tokens: 256,
        }),
        signal: ac.signal,
      });

      clearTimeout(timer);

      console.error("[approve] response status:", response.status);
      if (!response.ok) {
        const errText = await response.text().catch(() => "");
        console.error("[approve] response error body:", errText.slice(0, 500));
        return null;
      }

      const data = await response.json();
      const contentText = data.choices?.[0]?.message?.content;
      console.error("[approve] verdict text:", (contentText || "").slice(0, 200));
      const verdict = parseVerdictText(contentText);
      if (verdict) {
        console.error("[approve] model", spec, "verdict:", verdict.safe ? "SAFE" : "UNSAFE", "-", verdict.reason);
      }
      return verdict;
    } catch (err: any) {
      console.error("[approve] fetch exception for", spec, ":", err?.message || err);
      return null;
    }
  }

  async function classifyCommand(cmd: string, modelRegistry: any): Promise<{ safe: boolean; reason: string } | null> {
    const primary = readSmolModelSpec();
    if (!primary) { console.error("[approve] no smol model spec found"); return null; }

    const verdict = await tryModel(primary, cmd, modelRegistry);
    if (verdict) return verdict;

    const fallbacks = readFallbackChain();
    for (const spec of fallbacks) {
      if (spec === primary) continue;
      console.error("[approve] falling back to:", spec);
      const fbVerdict = await tryModel(spec, cmd, modelRegistry);
      if (fbVerdict) return fbVerdict;
    }

    return null;
  }

  // ============================================================
  // Hook handlers
  // ============================================================

  pi.on("session_start", async (_event: any, ctx: any) => {
    const mode = getMode();
    const sfp = settingsFilePath();
    ctx.ui.notify("Approval hook loaded — mode: " + mode + " (state: " + sfp + ")", "info");
  });

  pi.on("tool_call", async (event: any, ctx: any) => {
    const mode = getMode();

    // ---- Mode switching via omp-approve-mode command ----
    if (event.toolName === "bash") {
      const cmd = String(event.input.command ?? "").trim();
      const modeSwitch = cmd.match(/^omp-approve-mode\s+(normal|edits|auto)$/);
      if (modeSwitch) {
        const newMode = modeSwitch[1];
        setMode(newMode);
        ctx.ui.notify("Mode changed to: " + newMode, "success");
        return { block: true, reason: "Mode changed to " + newMode + ". Run your command again." };
      }
    }

    // ---- Edit/write tools (all modes — enforce Read/Edit/Write deny/allow rules) ----
    if (event.toolName === "edit" || event.toolName === "write") {
      const filePath = event.input?.path || event.input?.file || event.input?.filePath || "";
      let resolved = filePath;
      if (filePath.startsWith("local://")) {
        resolved = path.join(repoRoot(), filePath.slice("local://".length));
      } else if (!path.isAbsolute(filePath)) {
        resolved = path.resolve(repoRoot(), filePath);
      }

      // 1. Deny rules always enforced (all modes)
      const settings = loadSettings();
      const perms = settings.permissions as Record<string, unknown> | undefined;
      const deny: string[] = Array.isArray(perms?.deny) ? perms.deny as string[] : [];
      for (const rule of deny) {
        if (pathRuleMatches(rule, resolved)) {
          return { block: true, reason: "File blocked by deny rule: " + rule };
        }
      }

      // 2. Allow rules → auto-approve (all modes)
      const allow: string[] = Array.isArray(perms?.allow) ? perms.allow as string[] : [];
      for (const rule of allow) {
        if (pathRuleMatches(rule, resolved)) return;
      }

      // 3. Mode-specific auto-approval
      if (mode === "edits") {
        if (resolved.startsWith(repoRoot() + path.sep) || resolved === repoRoot()) {
          return; // auto-allow edits within repo in edits mode
        }
      }

      // 4. Fall through: prompt or block
      if (ctx.hasUI) {
        const ok = await ctx.ui.confirm("Edit file", "Allow edit to: " + filePath + "?");
        if (!ok) return { block: true, reason: "Edit denied" };
        return;
      }
      return { block: true, reason: "Edit blocked (no UI)" };
    }

    // ---- Bash commands ----
    if (event.toolName !== "bash") return;
    const cmd = String(event.input.command ?? "");

    // 1. Whitelist check (all modes) — checks permissions.allow / permissions.deny
    if (checkWhitelist(cmd)) return;

    // 2. Per-mode behavior
    if (mode === "auto") {
      // Local classifier runs first — deny patterns are non-negotiable.
      // Claude Code's architecture: allow/deny rules → file ops → classifier.
      // A compromised LLM must never override hardcoded unsafe patterns.
      const localVerdict = localClassify(cmd);

      if (!localVerdict.safe && localVerdict.definite) {
        // Matched a hardcoded unsafe pattern → always prompt, skip LLM entirely
        if (!ctx.hasUI) {
          return { block: true, reason: "Command blocked: " + localVerdict.reason };
        }
        const ok = await ctx.ui.confirm(
          "⚠ Unsafe command (policy)", cmd.slice(0, 200) + "\n\n" + localVerdict.reason + "\n\nAllow?");
        if (!ok) {
          ctx.ui.notify("Command denied", "error");
          return { block: true, reason: "Denied: " + localVerdict.reason };
        }
        ctx.ui.notify("Command approved by user", "success");
        return;
      }

      if (localVerdict.safe && localVerdict.definite) {
        // Local classifier says definitely safe → auto-allow
        return;
      }

      // Unrecognized by local classifier → consult LLM
      let verdict = await classifyCommand(cmd, ctx.modelRegistry);
      if (!verdict) {
        console.error("[approve] all LLM classifiers unreachable, using local fallback");
        ctx.ui.notify("LLM safety classifiers unreachable — prompting for unrecognized command", "warning");
        // Unrecognized + LLM unavailable → block (conservative)
        if (!ctx.hasUI) {
          return { block: true, reason: "Command blocked (unrecognized, LLM unreachable): " + localVerdict.reason };
        }
        const ok2 = await ctx.ui.confirm(
          "Unrecognized command", cmd.slice(0, 200) + "\n\n" + localVerdict.reason + "\n\nAllow?");
        if (!ok2) {
          ctx.ui.notify("Command denied", "error");
          return { block: true, reason: "Denied: " + localVerdict.reason };
        }
        ctx.ui.notify("Command approved by user", "success");
        return;
      }
      if (verdict.safe) return;

      if (!ctx.hasUI) {
        return { block: true, reason: "Command blocked: " + verdict.reason };
      }
      const ok3 = await ctx.ui.confirm(
        "Unsafe command", cmd.slice(0, 200) + "\n\n" + verdict.reason + "\n\nAllow?");
      if (!ok3) {
        ctx.ui.notify("Command denied", "error");
        return { block: true, reason: "Denied: " + verdict.reason };
      }
      ctx.ui.notify("Command approved by user", "success");
      return;
    }

    // Normal / Edits mode: user confirms, then optional whitelist
    const localVerdict = localClassify(cmd);
    const safetyLabel = localVerdict.safe ? "Approve command?" : "⚠ Potentially unsafe — approve?";

    if (!ctx.hasUI) {
      if (localVerdict.safe) return;
      return { block: true, reason: "Command blocked (no UI): " + localVerdict.reason };
    }

    const ok = await ctx.ui.confirm(
      safetyLabel,
      cmd.slice(0, 200) + "\n\n" + localVerdict.reason + "\n\nAllow this once?"
    );
    if (!ok) {
      ctx.ui.notify("Command denied", "error");
      return { block: true, reason: "Denied: " + localVerdict.reason };
    }

    // Offer to whitelist each subcommand separately
    // Compound commands (&&, ||, ;, |) are split so each gets its own rule
    const subcommands = splitCompoundCommands(cmd);
    const rules: string[] = [];
    for (const sub of subcommands) {
      const { rule } = generatePermissionRule(sub);
      if (!rules.includes(rule)) rules.push(rule);
    }
    if (rules.length === 0) {
      const { rule } = generatePermissionRule(cmd);
      rules.push(rule);
    }

    const ruleList = rules.map(r => "  " + r).join("\n");
    const whitelistOk = await ctx.ui.confirm(
      "Always allow?",
      "Rules:\n" + ruleList + "\n\nSaved to .claude/settings.local.json\nFuture matching commands will run without confirmation."
    );
    if (whitelistOk) {
      for (const rule of rules) addToWhitelist(rule);
      ctx.ui.notify("Allowed: " + rules.join(", "), "success");
    }

    ctx.ui.notify("Command approved by user", "success");
  });
}
