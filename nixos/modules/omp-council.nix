# Council agents for the `council` skill (.claude/skills/council). Everything
# here is generated: 19 task-agent files, one model role per agent, one fallback
# chain per agent, and the per-agent request budget. Imported by omp-config.nix.
{lib}: let
  # ---- configuration: edit here ----
  # name: short id used in agent names. model: provider/id. high/low: thinking
  # level of the creator tier and of the validator/judge tier. trust: weight of
  # this model's judge in the report's trust-weighted mean.
  members = [
    { name = "deepseek-flash";   model = "litellm/deepseek/deepseek-flash"; high = "max";   low = "low"; trust = 1.0; }
    { name = "claude-fable-5-2"; model = "anthropic/claude-fable-5-2";      high = "high";  low = "low"; trust = 1.0; }
    { name = "claude-opus-5-5";  model = "anthropic/claude-opus-5-5";       high = "xhigh"; low = "low"; trust = 1.0; }
    { name = "gemini-4-neon";    model = "litellm/gemini/gemini-4-neon";    high = "high";  low = "low"; trust = 1.0; }
  ];
  # Cheap shared workers every council agent may delegate to.
  tasks = {
    basic    = { model = "litellm/deepseek/deepseek-flash"; level = "low"; };
    advanced = { model = "litellm/deepseek/deepseek-flash"; level = "high"; };
    elite    = { model = "anthropic/claude-fable-5-2";      level = "high"; };
  };
  # A manager that dies loses the run, so managers may move to the same model
  # on the proxy's API-key lane. Set fallback = [] to make them quit instead.
  managers = {
    creator   = { model = "anthropic/claude-opus-5-5"; level = "high"; fallback = ["litellm/anthropic/claude-opus-5-5"]; };
    validator = { model = "anthropic/claude-opus-5-5"; level = "high"; fallback = ["litellm/anthropic/claude-opus-5-5"]; };
    judgement = { model = "anthropic/claude-opus-5-5"; level = "high"; fallback = ["litellm/anthropic/claude-opus-5-5"]; };
  };
  prepare = { model = "litellm/deepseek/deepseek-flash"; level = "high"; };
  quorum = 2;
  creatorRequestBudget = 1000;
  maxRecursionDepth = 5;
  # ---- end of configuration ----

  body = file: builtins.readFile (../../.omp/agent/council/bodies + "/${file}.md");
  schema = name: builtins.fromJSON (builtins.readFile (../../.omp/agent/council/schemas + "/${name}.json"));
  # role: creator, validator or judge. One agent carries one output schema, so
  # every member gets one agent per role.
  memberAgent = m: role: "council_member_${m.name}_${role}";
  taskSpawns = ["council_task_basic" "council_task_advanced" "council_task_super_elite"];

  memberAgents = lib.concatMap (m:
    map (role: {
      name = memberAgent m role;
      description = "Council member bound to one model and one role. Builds one deliverable, writes validation criteria, or scores anonymised deliverables for the council skill. Spawned only by council managers.";
      spawns = taskSpawns;
      inherit (m) model;
      level = if role == "creator" then m.high else m.low;
      schema = role;
      fallback = [];
      body = body "member";
    }) ["creator" "validator" "judge"])
  members;

  taskAgents = [
    {
      name = "council_task_basic";
      description = "Basic tasks, scouting, analysis, and other lightweight work for the council orchestration process.";
      spawns = ["council_task_basic"];
      inherit (tasks.basic) model level;
      fallback = [];
      body = body "task_basic";
    }
    {
      name = "council_task_advanced";
      description = "Harder tasks, coding, and orchestration for the council orchestration process.";
      spawns = ["council_task_basic" "council_task_advanced" "web-researcher"];
      inherit (tasks.advanced) model level;
      fallback = [];
      body = body "task_advanced";
    }
    {
      name = "council_task_super_elite";
      description = "Only the most difficult tasks and in-depth planning for the council orchestration process.";
      spawns = ["council_task_basic" "council_task_advanced"];
      inherit (tasks.elite) model level;
      fallback = [];
      body = body "task_super_elite";
    }
  ];

  managerAgents = [
    {
      name = "council_manager_creator";
      description = "Creator Council manager: gives one prompt to every council member's creator agent and records each deliverable's workspace and notes. Spawned only by the council skill.";
      spawns = map (m: memberAgent m "creator") members;
      inherit (managers.creator) model level fallback;
      body = body "manager_creator";
    }
    {
      name = "council_manager_validator";
      description = "Validator Council manager: collects validation criteria from every council member's validator agent and merges them into one rubric. Spawned only by the council skill.";
      spawns = map (m: memberAgent m "validator") members;
      inherit (managers.validator) model level fallback;
      schema = "rubric";
      body = body "manager_validator";
    }
    {
      name = "council_manager_judgement";
      description = "Judgement Council manager: gathers run-time evidence, has every council member's judge agent score the anonymised deliverables, and runs the report script. Spawned only by the council skill.";
      spawns = (map (m: memberAgent m "judge") members) ++ ["council_prepare_results"];
      inherit (managers.judgement) model level fallback;
      body = body "manager_judgement";
    }
  ];

  prepareAgent = {
    name = "council_prepare_results";
    description = "Builds and runs one council deliverable against the rubric's machine-checkable commands and saves the output as evidence. Spawned only by the Judgement Council manager.";
    spawns = ["council_task_basic"];
    inherit (prepare) model level;
    fallback = [];
    body = body "prepare_results";
  };

  agents = memberAgents ++ taskAgents ++ managerAgents ++ [prepareAgent];

  # model is a role alias, never a provider/id: a subagent on a role alias takes
  # that role's fallback chain, and an empty chain means "fail instead of
  # switching models" (omp task/executor.ts, resolveSubagentInheritedRetryFallbackChain).
  # An agent with a schema gets `structured: true` plus a JTD `output`, so it
  # returns through `yield` even with task.structured off. builtins.toJSON emits
  # one flow mapping, which the YAML frontmatter loader parses.
  agentFile = a: {
    name = ".omp/agent/agents/${a.name}.md";
    value.text =
      lib.concatStringsSep "\n" ([
          "---"
          "name: ${a.name}"
          "description: ${builtins.toJSON a.description}"
          "spawns: ${lib.concatStringsSep ", " a.spawns}"
          "model: \"@${a.name}\""
          "thinking-level: ${a.level}"
        ]
        ++ lib.optional (a ? schema) "structured: true"
        ++ lib.optional (a ? schema) "output: ${builtins.toJSON (schema a.schema)}"
        ++ ["---" ""])
      + "\n"
      + a.body;
  };

  roster = {
    inherit quorum;
    prepare_agent = prepareAgent.name;
    members = map (m: {
      inherit (m) name trust;
      creator_agent = memberAgent m "creator";
      validator_agent = memberAgent m "validator";
      judge_agent = memberAgent m "judge";
    }) members;
  };
in {
  inherit maxRecursionDepth;

  homeFiles =
    lib.listToAttrs (map agentFile agents)
    // {".omp/agent/council/roster.json".text = builtins.toJSON roster;};

  # Lines for config.yml. Nix strips the 6-space common indentation of that
  # `''` body before interpolation, and an interpolated value keeps the indentation
  # of its first line only. So the separators below are the *post-strip* site
  # indentation: 2 spaces under `modelRoles:` (written at 8 in omp-config.nix),
  # 4 under `fallbackChains:` (written at 10). Re-check both if that block moves.
  modelRolesYaml =
    lib.concatStringsSep "\n  "
    (map (a: "${builtins.toJSON a.name}: ${builtins.toJSON "${a.model}:${a.level}"}") agents);
  fallbackChainsYaml =
    lib.concatStringsSep "\n    "
    (map (a: "${builtins.toJSON a.name}: ${builtins.toJSON a.fallback}") agents);
  agentSoftRequestBudgetJson = builtins.toJSON (lib.listToAttrs (map (m: {
      name = memberAgent m "creator";
      value = creatorRequestBudget;
    })
    members));
}
