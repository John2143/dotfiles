{
  config,
  pkgs,
  ...
}: let
  # Antigravity CLI (agy) gets the same skills and task agents as OMP and
  # Claude Code, plus OMP's SYSTEM.md as its global rules.
  #
  # agy skips any skill whose SKILL.md (or skill folder) is a symlink, so the
  # per-file home.file links OMP and Claude Code use would load nothing.
  # Instead skills.json and agents.json name real directories in the store;
  # a symlinked manifest, or a symlink above the skill folders, is fine.
  # These are agy's lowest-priority "declared" customizations: anything
  # written by hand under ~/.gemini/config/skills/ wins on a name clash.
  python = pkgs.python3.withPackages (p: [p.pyyaml]);

  # Same source as OMP and Claude Code, rewritten for agy's strict YAML and
  # its lack of allowed-tools — see nixos/scripts/convert-skills.py.
  skills = pkgs.runCommandLocal "agy-skills" {nativeBuildInputs = [python];} ''
    cp -r ${../../.claude/skills} $out
    chmod -R u+w $out
    find $out -name SKILL.md -exec python3 ${../scripts/convert-skills.py} --agy $out {} +
  '';

  agents = pkgs.runCommandLocal "agy-agents" {nativeBuildInputs = [python];} ''
    mkdir $out
    python3 ${../scripts/agy-agents.py} $out ${../../.omp/agent/agents}/*.md
  '';
in {
  home.file = {
    ".gemini/config/skills.json".text = builtins.toJSON {entries = [{path = "${skills}";}];};
    ".gemini/config/agents.json".text = builtins.toJSON {entries = [{path = "${agents}";}];};
    # 16 KB, under agy's 24 KB per-rule-file cap. Lines about OMP-only tools
    # (eval, IRC, async jobs) come along; agy has no such tools and skips them.
    ".gemini/GEMINI.md".source = config.home.file.".omp/agent/SYSTEM.md".source;
  };
}
