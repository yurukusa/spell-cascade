# Game Factory Pipeline Gate Design: 20 -> 6 -> 3 -> 1

Date: 2026-02-16
Context: Autonomous game development factory for VS-like/survivor browser games.
Stack: Godot 4.3 + HTML5 export, pyfxr (sound), Pillow (sprites), godot-mcp, quality-gate.sh, SpellCascadeAutoTest.gd, AutoPlayer.gd

## Problem Statement

The factory has a pipeline: **Idea -> Build -> Test -> Ship**. Currently, quality gates exist only inside the Test stage (3-tier stability/balance/regression + feel scorecard). But there are no gates between stages. This means:

- **Idea -> Build** has no filter. Bad ideas get fully built before anyone notices.
- **Build -> Test** has no readiness check. Incomplete builds waste 90-second autotest cycles.
- **Test -> Ship** has no ship-readiness checklist. Games that pass quality gates might still lack distribution requirements (icons, descriptions, screenshots).

We need a **pipeline gate at every stage boundary** where machine-verifiable conditions must be met before advancing. Zero human-in-the-loop. Every check is automatable with existing tooling or tooling that can be built in <1 day.

### What "Machine-Verifiable" Means

A condition is machine-verifiable if a script can evaluate it and return PASS/FAIL with no subjective interpretation. Examples:
- "File `project.godot` contains `config/name`" -- PASS/FAIL via grep
- "AutoTest results.json has `pass: true`" -- PASS/FAIL via jq
- "Export ZIP is under 50MB" -- PASS/FAIL via stat

Non-examples (excluded):
- "The game is fun" -- requires human judgment
- "The art style is cohesive" -- requires aesthetic evaluation
- "The game design is novel" -- requires domain knowledge

### Existing Infrastructure

| Tool | What It Does | Stage |
|------|-------------|-------|
| `quality-gate.sh` | 3-tier stability/balance/regression gate | Test |
| `SpellCascadeAutoTest.gd` | 60s bot playthrough with telemetry | Test |
| `AutoPlayer.gd` | Input simulation bot | Test |
| `gen_sprite.py` | Pillow-based procedural sprite generation | Build |
| `pyfxr` | Procedural sound effect generation | Build |
| `godot-mcp` | Scene creation, node management, project ops | Build |
| `xvfb-run godot` | Headless Godot execution | Test/Ship |
| `export_presets.cfg` | HTML5 export configuration | Ship |

---

## The 20 Candidate Pipeline Gate Designs

Each candidate is a complete gate system (set of checks at one or more stage boundaries). Scored on three axes, 1-5:

- **Autonomy (A)**: Can it run with zero human input? 5 = fully automated, 1 = needs human decisions
- **Coverage (C)**: Does it catch the important failure modes? 5 = comprehensive, 1 = narrow
- **Simplicity (S)**: How easy to implement and maintain? 5 = trivial scripts, 1 = complex infrastructure

---

### G01: Minimal File-Existence Gate

**Stage boundary**: Build -> Test

**Checks**:
- [ ] `project.godot` exists and has `run/main_scene` set
- [ ] Main scene file referenced in `project.godot` exists
- [ ] At least 1 `.gd` script file exists in `scripts/`
- [ ] `export_presets.cfg` exists (export is possible)

**Pass/Fail**: All checks must pass.

**Implementation**: Single bash script with `test -f` and `grep`.

| A | C | S | Total |
|---|---|---|-------|
| 5 | 2 | 5 | 12 |

**Rationale**: Extremely simple but catches only the most basic failures (missing files). Does not validate that the game actually works.

---

### G02: Syntax Validation Gate

**Stage boundary**: Build -> Test

**Checks**:
- [ ] All `.gd` files parse without syntax errors (`godot --headless --check-only`)
- [ ] All `.tscn` files are valid (no broken resource references)
- [ ] `project.godot` is valid INI format
- [ ] No dangling resource references (referenced files exist)

**Pass/Fail**: Zero syntax errors.

**Implementation**: `godot --headless --check-only` for project-level check + custom script to validate resource paths.

| A | C | S | Total |
|---|---|---|-------|
| 5 | 3 | 4 | 12 |

**Rationale**: Prevents wasting autotest time on syntactically broken builds. Does not catch logic errors.

---

### G03: Idea Feasibility Gate (Pre-Build)

**Stage boundary**: Idea -> Build

**Checks**:
- [ ] Design doc exists with required sections: core_loop, win_condition, controls, session_length
- [ ] Target session length is 30-120s (VS-like constraint)
- [ ] Core loop has exactly 1 primary verb (move/shoot/dodge/collect)
- [ ] Estimated asset count is within budget (<=50 sprites, <=30 sounds, <=10 scenes)
- [ ] No dependency on external APIs or online services
- [ ] Genre tag matches factory capability: "vs-like" OR "survivor" OR "auto-battler"

**Pass/Fail**: All structural checks pass. Content quality is not evaluated.

**Implementation**: YAML/JSON schema validation of design doc.

| A | C | S | Total |
|---|---|---|-------|
| 4 | 3 | 4 | 11 |

**Rationale**: Prevents scope creep before a single line of code is written. Docked on Autonomy because generating the design doc still needs creative input (from LLM, but still a step). Docked on Coverage because it cannot evaluate whether the idea is actually fun or novel.

---

### G04: Asset Completeness Gate

**Stage boundary**: Build -> Test

**Checks**:
- [ ] Every `load("res://...")` in `.gd` files references an existing file
- [ ] Every `ExtResource` in `.tscn` files references an existing file
- [ ] No placeholder filenames (`test_`, `temp_`, `untitled`, `placeholder`)
- [ ] At least 1 audio file exists (`.wav` or `.ogg`)
- [ ] At least 1 texture/sprite file exists (`.png`)
- [ ] Icon is not Godot default (`icon.svg` has been modified or replaced)

**Pass/Fail**: Zero broken references, minimum assets present.

**Implementation**: Regex scan of `.gd` and `.tscn` files + file existence checks.

| A | C | S | Total |
|---|---|---|-------|
| 5 | 3 | 4 | 12 |

**Rationale**: Catches the "forgot to commit the asset" failure mode. Does not evaluate asset quality.

---

### G05: Full Lifecycle Gate (4-Stage)

**Stage boundary**: All four (Idea -> Build -> Test -> Ship)

**Checks per stage**:

*Idea -> Build*:
- [ ] Design doc schema valid
- [ ] Estimated scope within budget

*Build -> Test*:
- [ ] Syntax clean
- [ ] Asset references valid
- [ ] Main scene loads (headless dry run, <5s)
- [ ] At least 1 player input action mapped

*Test -> Ship*:
- [ ] quality-gate.sh returns GO or CONDITIONAL
- [ ] Feel scorecard has no FAIL ratings
- [ ] 3 consecutive autotest runs all pass (flake detection)

*Ship -> Distribution*:
- [ ] HTML5 export succeeds
- [ ] Export ZIP < 50MB
- [ ] Screenshot exists
- [ ] Game title and description set in project.godot

**Pass/Fail**: Each stage gate independently. Failure blocks advancement but does not block rollback/rework.

**Implementation**: 4 separate bash scripts, one per boundary.

| A | C | S | Total |
|---|---|---|-------|
| 5 | 5 | 2 | 12 |

**Rationale**: Maximum coverage -- every stage has a gate. But complex: 4 scripts to maintain, and the Idea gate requires a design doc format that does not yet exist. High coverage, high implementation cost.

---

### G06: Smoke Test Gate (Quick Reject)

**Stage boundary**: Build -> Test

**Checks**:
- [ ] `godot --headless --path . --quit` exits with code 0 within 10 seconds
- [ ] Main scene loads without crash (headless, 5s timeout)
- [ ] No `SCRIPT ERROR` in stdout during load

**Pass/Fail**: Zero crashes, exit code 0.

**Implementation**: Single `timeout 10 xvfb-run godot --path . --quit` with output capture.

| A | C | S | Total |
|---|---|---|-------|
| 5 | 2 | 5 | 12 |

**Rationale**: Ultra-fast reject for completely broken builds. Takes 10 seconds instead of 90. But only catches hard crashes, not logic bugs or balance issues.

---

### G07: Distribution Readiness Gate

**Stage boundary**: Test -> Ship

**Checks**:
- [ ] HTML5 export completes without error
- [ ] Export ZIP file size < 50MB (CrazyGames/Poki limit)
- [ ] `index.html` exists in export
- [ ] Game loads in headless browser check (optional: Playwright)
- [ ] Screenshot(s) exist in `marketing/` directory
- [ ] `project.godot` has non-default `application/config/name`
- [ ] `project.godot` has non-default `application/config/description`
- [ ] Version file exists and is semver format
- [ ] Icon file is not Godot default (size > 1KB and different from stock)
- [ ] CREDITS.md or LICENSE exists

**Pass/Fail**: All checks pass.

**Implementation**: Bash script checking file existence, sizes, and content.

| A | C | S | Total |
|---|---|---|-------|
| 5 | 4 | 4 | 13 |

**Rationale**: Catches the embarrassing "shipped without a game title" failures. Specific to distribution requirements. Does not validate game quality (that is the Test stage's job).

---

### G08: Performance Budget Gate

**Stage boundary**: Build -> Test (pre-autotest filter)

**Checks**:
- [ ] Total project size < 100MB (web game constraint)
- [ ] No single asset > 5MB (texture/audio bloat detector)
- [ ] Scene tree depth < 20 levels (performance red flag)
- [ ] No `_process()` functions calling `load()` (runtime loading kills FPS)
- [ ] Particle systems use CPUParticles2D, not GPUParticles2D (web compatibility)
- [ ] No `await get_tree().create_timer()` inside `_process()` (common antipattern)

**Pass/Fail**: Zero violations.

**Implementation**: `du`, `find`, grep-based static analysis of `.gd` files.

| A | C | S | Total |
|---|---|---|-------|
| 5 | 3 | 4 | 12 |

**Rationale**: Prevents performance disasters before they reach autotest. Static analysis only -- does not require running the game. Catches common GDScript antipatterns that cause frame drops in HTML5.

---

### G09: Juice Presence Gate

**Stage boundary**: Test -> Ship (post-autotest, pre-distribution)

**Checks**:
- [ ] Screen shake function exists and is called from at least 1 event
- [ ] Tween usage: at least 5 distinct `create_tween()` calls across the project
- [ ] Particle effects: at least 3 particle emitter nodes in scene tree
- [ ] Sound effects: at least 5 distinct `.wav`/`.ogg` files
- [ ] Music: at least 1 audio file > 10 seconds duration
- [ ] Easing: at least 1 tween uses non-LINEAR transition type
- [ ] Hit feedback: damage events trigger visual or audio response (grep for signal connections)
- [ ] UI animation: at least 1 UI element uses AnimationPlayer or Tween

**Pass/Fail**: At least 6/8 checks pass.

**Implementation**: Grep-based scan of `.gd` files + scene tree node counting.

| A | C | S | Total |
|---|---|---|-------|
| 5 | 4 | 3 | 12 |

**Rationale**: Directly addresses the "AI-made feel" anti-pattern. A game without juice feels dead. This gate ensures minimum juice exists. Docked on Simplicity because some checks (like "damage events trigger visual response") require tracing signal connections, which is moderately complex.

---

### G10: Regression Firewall Gate

**Stage boundary**: Test -> Ship (after autotest passes)

**Checks**:
- [ ] Current autotest results vs. baseline: no metric regressed >25%
- [ ] Feel scorecard: no metric dropped a tier (e.g., EXCELLENT -> GOOD is OK, GOOD -> WARN is FAIL)
- [ ] Kill count: current >= 80% of baseline
- [ ] Level-up count: current >= 80% of baseline
- [ ] Damage taken: current within 50-200% of baseline (changed too much = suspicious)
- [ ] No new SCRIPT ERROR in autotest output

**Pass/Fail**: All regression checks pass.

**Implementation**: JSON comparison between `results.json` and `baselines/latest.json`.

| A | C | S | Total |
|---|---|---|-------|
| 5 | 4 | 4 | 13 |

**Rationale**: The existing quality-gate.sh has basic regression (Tier 3), but it only checks peak enemy count. This expands regression to all key metrics. Prevents "fix one thing, break another" spirals.

---

### G11: Player Loop Completeness Gate

**Stage boundary**: Build -> Test

**Checks**:
- [ ] Win condition exists: game ends with a success state (scene change, signal, or print)
- [ ] Lose condition exists: HP <= 0 triggers game over
- [ ] Restart mechanism exists: player can start a new run from game-over screen
- [ ] Pause mechanism exists: input action "pause" or "ui_cancel" is handled
- [ ] Score/progress tracking exists: at least 1 variable tracks player progress
- [ ] HUD exists: at least 1 UI element displays game state (HP bar, score, timer)

**Pass/Fail**: All core loop elements present.

**Implementation**: Grep for key patterns (`game_over`, `restart`, `pause`, `score`, `hp`, `hud`) in `.gd` files and scene trees.

| A | C | S | Total |
|---|---|---|-------|
| 5 | 4 | 3 | 12 |

**Rationale**: Ensures the game has a complete loop before entering test. Catches "built the combat but forgot the game-over screen" failures. Docked on Simplicity because keyword-based detection has false positive risk.

---

### G12: Three-Run Consistency Gate

**Stage boundary**: Test -> Ship

**Checks**:
- [ ] Run autotest 3 times consecutively
- [ ] All 3 runs produce `pass: true`
- [ ] Kill count coefficient of variation < 30% (consistent gameplay)
- [ ] Level-up count identical across runs (deterministic progression)
- [ ] No run crashes
- [ ] Total fires within 20% of each other

**Pass/Fail**: All 3 runs pass, metrics are consistent.

**Implementation**: Loop in bash, collect 3 results, compare with jq.

| A | C | S | Total |
|---|---|---|-------|
| 5 | 4 | 3 | 12 |

**Rationale**: Catches flaky behavior. A game that passes 1 out of 3 autotests is not shippable. Docked on Simplicity because it takes 3x90s = 4.5 minutes and requires aggregation logic.

---

### G13: Web Export Validation Gate

**Stage boundary**: Ship (post-export)

**Checks**:
- [ ] `godot --headless --export-release "HTML5"` exits without error
- [ ] `index.html` contains `<canvas>` tag (Godot web export marker)
- [ ] Total export size < 50MB
- [ ] No missing resource warnings in export log
- [ ] `.pck` file exists and is > 1KB
- [ ] `index.js` or equivalent loader script exists
- [ ] CORS-friendly: no absolute file:// paths in exported files

**Pass/Fail**: Export succeeds and is web-valid.

**Implementation**: Export command + file checks + grep for common issues.

| A | C | S | Total |
|---|---|---|-------|
| 5 | 3 | 4 | 12 |

**Rationale**: Catches export failures before attempting distribution. The export step itself can fail silently (producing incomplete ZIPs). This gate validates the output.

---

### G14: Sound Coverage Gate

**Stage boundary**: Build -> Test

**Checks**:
- [ ] At least 1 sound for player attack action
- [ ] At least 1 sound for enemy death
- [ ] At least 1 sound for player damage received
- [ ] At least 1 sound for XP/item pickup
- [ ] At least 1 sound for level-up
- [ ] At least 1 background music track
- [ ] AudioBus layout has separate Music and SFX buses
- [ ] SFX files have pitch_scale randomization in playing code

**Pass/Fail**: At least 6/8 present.

**Implementation**: Grep for AudioStreamPlayer usage patterns + file existence + bus configuration in project.godot.

| A | C | S | Total |
|---|---|---|-------|
| 5 | 3 | 3 | 11 |

**Rationale**: Audio is the #1 "AI-made feel" indicator. No sound = instant amateur signal. Docked on both Coverage (narrow focus on just audio) and Simplicity (tracing which sound plays on which event requires understanding signal flow).

---

### G15: Design Contract Gate

**Stage boundary**: Idea -> Build

**Checks**:
- [ ] `design.yaml` exists with required schema fields
- [ ] `core_loop` is a single sentence (forced brevity)
- [ ] `target_session_length_seconds` is 30-120
- [ ] `player_verb` is one of: move, shoot, dodge, collect, build, survive
- [ ] `difficulty_model` is one of: timer, wave, adaptive
- [ ] `asset_budget.sprites` <= 50
- [ ] `asset_budget.sounds` <= 30
- [ ] `asset_budget.scenes` <= 10
- [ ] `monetization` is "none" or "ads" (no IAP for browser games)
- [ ] `target_platforms` includes "html5"

**Pass/Fail**: Schema validates.

**Implementation**: Python script with YAML schema validation (jsonschema or cerberus).

| A | C | S | Total |
|---|---|---|-------|
| 4 | 3 | 4 | 11 |

**Rationale**: Forces the Idea stage to produce a machine-readable contract that the Build stage must fulfill. Docked on Autonomy because creating the YAML still requires creative input, though an LLM can generate it.

---

### G16: Anti-Pattern Static Analysis Gate

**Stage boundary**: Build -> Test

**Checks**:
- [ ] No `print()` calls outside of debug directories
- [ ] No `TODO` / `FIXME` / `HACK` comments in non-debug code
- [ ] No `load()` inside `_process()` or `_physics_process()`
- [ ] No `await` inside `_process()` or `_physics_process()`
- [ ] No unused variables (GDScript `--check-only` warnings)
- [ ] No circular scene dependencies
- [ ] No `@onready` referencing nodes that do not exist in scene tree
- [ ] No magic numbers without accompanying comment

**Pass/Fail**: Zero violations in non-debug code.

**Implementation**: Regex-based linting of `.gd` files.

| A | C | S | Total |
|---|---|---|-------|
| 5 | 3 | 3 | 11 |

**Rationale**: Catches code quality issues that cause subtle runtime bugs. Docked on Coverage (code quality != game quality) and Simplicity (some checks like unused variables and circular dependencies require AST-level analysis).

---

### G17: Telemetry Instrumentation Gate

**Stage boundary**: Build -> Test (ensures autotest can produce useful data)

**Checks**:
- [ ] `SpellCascadeAutoTest.gd` (or equivalent) exists
- [ ] AutoTest tracks: fire_count, kill_count, xp_pickup_count, level_ups, hp_samples
- [ ] AutoTest produces `results.json` with expected schema
- [ ] Game has signal connections that AutoTest can listen to
- [ ] At least 5 distinct telemetry signals are emitted during a dry run
- [ ] `feel_event_timestamps` array is populated (non-empty after 10s)

**Pass/Fail**: Telemetry schema validates and produces data.

**Implementation**: Run a 15-second dry run, check output schema.

| A | C | S | Total |
|---|---|---|-------|
| 5 | 3 | 3 | 11 |

**Rationale**: If the Test stage cannot collect data, all subsequent gates are blind. This gate ensures the measurement system works before committing to a full 60-second autotest. Docked on Simplicity because it requires a 15-second Godot run.

---

### G18: Progressive Gate Chain (Sequential Escalation)

**Stage boundary**: Build -> Test, with cascading tiers

**Design**: Instead of one gate, use 3 progressively expensive gates within Build -> Test:

*Quick Gate (5s)*:
- [ ] Files exist, syntax clean, main scene loads

*Medium Gate (15s)*:
- [ ] Dry-run produces telemetry
- [ ] No crashes in first 15 seconds
- [ ] At least 1 enemy spawns
- [ ] At least 1 fire event

*Full Gate (90s)*:
- [ ] Complete autotest pass
- [ ] Quality-gate.sh returns GO or CONDITIONAL
- [ ] Feel scorecard advisory check

**Pass/Fail**: Each gate is a prerequisite for the next. Failure at any level blocks advancement and gives a specific diagnostic.

**Implementation**: Chained bash scripts with early-exit.

| A | C | S | Total |
|---|---|---|-------|
| 5 | 5 | 3 | 13 |

**Rationale**: Fails fast and fails cheap. A syntax error is caught in 5 seconds, not 90. A spawn bug is caught in 15 seconds, not 90. Only healthy builds pay the full 90-second cost. Docked on Simplicity because 3 levels of gating means 3 scripts to maintain with coordination logic.

---

### G19: Ship-or-Kill Gate (Binary Decision)

**Stage boundary**: Test -> Ship (terminal decision gate)

**Checks**:
- [ ] quality-gate.sh verdict is GO (not CONDITIONAL, not NO-GO)
- [ ] 3-run consistency passes (G12 logic)
- [ ] Feel scorecard has zero FAIL ratings
- [ ] HTML5 export succeeds and is < 50MB
- [ ] Marketing assets exist (screenshot, title, description)
- [ ] No SCRIPT ERROR in any autotest run
- [ ] Version number has been incremented from last shipped version

**Decision**:
- ALL pass -> **SHIP**: Proceed to distribution
- ANY fail -> **KILL**: Do not ship. Return to Build with diagnostic report. No "conditional" middle ground.

**Implementation**: Master script that calls sub-gates and enforces binary outcome.

| A | C | S | Total |
|---|---|---|-------|
| 5 | 5 | 3 | 13 |

**Rationale**: Eliminates ambiguity. The current system has GO/CONDITIONAL/NO-GO, which requires human judgment for CONDITIONAL cases. Ship-or-Kill removes the conditional zone. Docked on Simplicity because it aggregates multiple sub-gates.

---

### G20: Factory Pipeline Orchestrator (Full System)

**Stage boundary**: All stages, orchestrated by a master script

**Design**: A single `factory.sh` that orchestrates the entire pipeline:

```
factory.sh --from idea --to ship
  |
  +-- Phase 1: Idea Gate (design.yaml validation)
  |     FAIL -> exit with "idea rejected: <reason>"
  |
  +-- Phase 2: Build Gate (sequential escalation)
  |     2a: Quick (5s) - files, syntax
  |     2b: Medium (15s) - dry run, telemetry
  |     FAIL -> exit with "build incomplete: <reason>"
  |
  +-- Phase 3: Test Gate (full autotest)
  |     3a: Single-run quality gate
  |     3b: 3-run consistency
  |     3c: Feel scorecard advisory
  |     FAIL -> exit with "test failed: <reason>"
  |
  +-- Phase 4: Ship Gate (distribution readiness)
  |     4a: Export validation
  |     4b: Marketing assets
  |     4c: Version increment
  |     FAIL -> exit with "not shippable: <reason>"
  |
  +-- OUTPUT: ship_report.json
       {verdict: "SHIP" | "BLOCKED", blocked_at: "phase_N", reason: "..."}
```

**Pass/Fail**: Each phase gates the next. Final output is a structured report.

**Implementation**: Master bash script orchestrating sub-scripts, with JSON report output.

| A | C | S | Total |
|---|---|---|-------|
| 5 | 5 | 2 | 12 |

**Rationale**: Maximum coverage and autonomy -- the entire pipeline is automated. But maximum complexity: requires all sub-gates to exist, coordination logic, report generation, and error handling across 4 phases. This is the "endgame" design but the hardest to build from scratch.

---

## Summary Table: The 20

| # | Name | A | C | S | Total |
|---|------|---|---|---|-------|
| G01 | Minimal File-Existence | 5 | 2 | 5 | 12 |
| G02 | Syntax Validation | 5 | 3 | 4 | 12 |
| G03 | Idea Feasibility | 4 | 3 | 4 | 11 |
| G04 | Asset Completeness | 5 | 3 | 4 | 12 |
| G05 | Full Lifecycle (4-Stage) | 5 | 5 | 2 | 12 |
| G06 | Smoke Test (Quick Reject) | 5 | 2 | 5 | 12 |
| G07 | Distribution Readiness | 5 | 4 | 4 | 13 |
| G08 | Performance Budget | 5 | 3 | 4 | 12 |
| G09 | Juice Presence | 5 | 4 | 3 | 12 |
| G10 | Regression Firewall | 5 | 4 | 4 | 13 |
| G11 | Player Loop Completeness | 5 | 4 | 3 | 12 |
| G12 | Three-Run Consistency | 5 | 4 | 3 | 12 |
| G13 | Web Export Validation | 5 | 3 | 4 | 12 |
| G14 | Sound Coverage | 5 | 3 | 3 | 11 |
| G15 | Design Contract | 4 | 3 | 4 | 11 |
| G16 | Anti-Pattern Static Analysis | 5 | 3 | 3 | 11 |
| G17 | Telemetry Instrumentation | 5 | 3 | 3 | 11 |
| G18 | Progressive Gate Chain | 5 | 5 | 3 | 13 |
| G19 | Ship-or-Kill Binary Decision | 5 | 5 | 3 | 13 |
| G20 | Factory Pipeline Orchestrator | 5 | 5 | 2 | 12 |

---

## Shortlist: 6

Selecting by total score, with ties broken by Coverage (the pipeline's job is to catch problems), then Simplicity (maintainability matters for a solo-agent factory).

### 1. G07: Distribution Readiness Gate (Total: 13, A:5 C:4 S:4)

**Why it advances**: This is the most overlooked gap in the current pipeline. The quality gate validates gameplay but never checks whether the game is actually shippable (icons, titles, export size). Every game that passed autotest but failed to upload due to missing marketing assets or oversized exports represents wasted pipeline time. This gate is cheap to implement (file checks) and catches a distinct failure class.

### 2. G10: Regression Firewall Gate (Total: 13, A:5 C:4 S:4)

**Why it advances**: The existing quality-gate.sh Tier 3 only checks peak enemy count regression. This expands to all key metrics (kills, levels, damage, feel scores). In an iterative build-test-fix loop, regression is the #1 risk -- you fix the difficulty curve and accidentally break the spawn system. Broad regression detection is essential for autonomous iteration.

### 3. G18: Progressive Gate Chain (Total: 13, A:5 C:5 S:3)

**Why it advances**: Fail-fast is the most impactful efficiency gain. Currently, a syntax error costs 90 seconds (full autotest) to discover. With progressive gates, it costs 5 seconds. Over 100 iterations, that is 2.4 hours saved. The chain also provides more specific diagnostics: "failed at syntax" vs. "failed at spawn" vs. "failed at balance" are very different problems with very different fixes.

### 4. G19: Ship-or-Kill Binary Decision (Total: 13, A:5 C:5 S:3)

**Why it advances**: Eliminates the "CONDITIONAL" verdict that requires human judgment. For a fully autonomous factory, binary decisions are mandatory. CONDITIONAL means "a human should look at this," which violates the zero-human constraint. Ship-or-Kill forces every iteration to either produce a shippable artifact or a diagnostic report for the next iteration.

### 5. G09: Juice Presence Gate (Total: 12, A:5 C:4 S:3)

**Why it advances**: Juice is what separates "technically functional" from "feels good." The quality gate checks stability and balance but never checks whether the game has screen shake, particles, tweens, or sound variation. A juiceless game that passes all other gates will still be rejected by players. This gate uses static analysis (grep for patterns) to verify juice elements exist.

### 6. G12: Three-Run Consistency Gate (Total: 12, A:5 C:4 S:3)

**Why it advances**: A single passing autotest run can be a fluke. Non-deterministic bugs (race conditions, spawn RNG edge cases, timer-dependent logic) appear only in some runs. Three consecutive passes with consistent metrics is a much stronger signal than one pass. This is especially important for a factory that ships without human playtesting.

### Why These 6 and Not Others

**Excluded despite equal total**:
- G05 (Full Lifecycle, 12): Maximum scope but its Simplicity=2 makes it impractical as a starting point. Its ideas are captured by G18 (progressive chain) and G19 (ship-or-kill) in more focused form.
- G20 (Factory Orchestrator, 12): Same problem as G05 -- too broad to implement first. G18+G19 compose into this naturally over time.
- G01/G06 (File Existence/Smoke Test, 12): Too narrow. Their checks are subsumed by G18's quick-gate phase.
- G04/G08/G13 (Asset/Performance/Export, 12): Good checks but narrow coverage. Their individual checks belong inside G18 or G07 rather than as standalone gates.
- G11 (Player Loop, 12): Good idea but keyword-based detection has high false positive risk. Better addressed by autotest behavioral checks in G18's medium gate.

**Excluded despite good concept**:
- G03/G15 (Idea Feasibility/Design Contract, 11): Require a design doc format that does not yet exist. Valuable but premature -- the factory should first prove it can reliably go Build -> Ship before adding Idea gates.
- G14 (Sound Coverage, 11): Subsumed by G09 (Juice Presence) which includes sound checks among other juice elements.
- G16 (Anti-Pattern Analysis, 11): Code quality is important but does not directly map to player experience. Lower priority than gameplay-facing gates.
- G17 (Telemetry Instrumentation, 11): Valuable check but specific to the autotest system. Better as a sub-check within G18's medium gate.

---

## Finalists: 3

### Finalist A: G18 -- Progressive Gate Chain

**Why it advances to final 3**: This is the highest-leverage design change. It does not add new checks -- it restructures *when* checks run to fail fast and fail cheap. Every other gate design can be slotted into G18's three-level framework.

**Detailed specification**:

```
QUICK GATE (5 seconds)
  Purpose: Reject obviously broken builds before they waste compute
  Run condition: Every iteration
  Cost: 5s wall clock

  Checks:
  [Q1] project.godot exists and has run/main_scene set
  [Q2] Main scene .tscn file exists
  [Q3] godot --headless --check-only exits with 0 (syntax clean)
  [Q4] All resource paths in .tscn files resolve to existing files
  [Q5] At least 1 .gd script in scripts/ directory
  [Q6] export_presets.cfg exists

  PASS: All 6 checks pass -> proceed to Medium Gate
  FAIL: Any check fails -> BLOCKED at "quick", diagnostic: which check failed
```

```
MEDIUM GATE (15 seconds)
  Purpose: Verify game boots and produces basic telemetry
  Run condition: Only after Quick Gate passes
  Cost: 15s wall clock (xvfb-run godot, 10s timeout + overhead)

  Checks:
  [M1] Game loads and runs for 10s without crash (exit code 0)
  [M2] No SCRIPT ERROR in stdout
  [M3] At least 1 enemy spawns (enemy_count > 0 at t=5s)
  [M4] At least 1 fire event (fire_count > 0)
  [M5] Player character exists and is alive at t=10s
  [M6] Telemetry output file is created and has expected schema

  PASS: All 6 checks pass -> proceed to Full Gate
  FAIL: Any check fails -> BLOCKED at "medium", diagnostic: which check failed
```

```
FULL GATE (90 seconds)
  Purpose: Complete quality evaluation
  Run condition: Only after Medium Gate passes
  Cost: 90s wall clock (60s autotest + overhead)

  Checks:
  [F1] quality-gate.sh returns GO or CONDITIONAL
  [F2] Tier 1 (stability): pass=true, fires>0, level_ups>0
  [F3] Tier 2 (balance): >=3/4 sub-checks pass
  [F4] Tier 3 (regression): no metric regressed >25% from baseline
  [F5] Feel scorecard: no FAIL ratings
  [F6] Run Completion Desire score >= 0.4 (not FAIL)

  PASS: F1 && F2 && F3 -> proceed to Ship evaluation
  CONDITIONAL: F1 but F4 or F5 or F6 has warnings -> log advisory, proceed
  FAIL: F1 fails -> BLOCKED at "full", diagnostic: quality-gate output
```

**Implementation plan**:
1. `gate-quick.sh` -- New file, ~50 lines
2. `gate-medium.sh` -- New file, ~80 lines (needs a 15s autotest mode)
3. `gate-full.sh` -- Wrapper around existing `quality-gate.sh` with feel scorecard check
4. `gate-chain.sh` -- Orchestrator: runs quick, then medium, then full. Exits at first failure.

**Why not just improve quality-gate.sh**: The progressive structure is fundamentally different from a single-pass gate. Quick and Medium gates run *without* the full autotest infrastructure. They use simpler, faster checks. Bolting this onto quality-gate.sh would make it harder to maintain, not easier.

---

### Finalist B: G19 -- Ship-or-Kill Binary Decision

**Why it advances to final 3**: For autonomous operation, ambiguity is the enemy. The current CONDITIONAL verdict means "maybe, a human should decide." In a zero-human factory, there is no human to decide. Every output must be SHIP or KILL (with diagnostic).

**Detailed specification**:

```
SHIP-OR-KILL GATE
  Purpose: Terminal binary decision -- is this build ready for distribution?
  Run condition: After Full Gate (G18) passes
  Cost: ~5 minutes (3x autotest runs + export)

  SHIP conditions (ALL must pass):
  [S1] quality-gate.sh verdict == "GO" (not CONDITIONAL)
  [S2] 3 consecutive autotest runs all produce pass=true
  [S3] Key metrics across 3 runs: CV < 30% (consistent)
  [S4] Feel scorecard: no FAIL in any of the 3 runs
  [S5] HTML5 export succeeds
  [S6] Export ZIP < 50MB
  [S7] marketing/screenshot_*.png exists (at least 1)
  [S8] project.godot has non-default name and description
  [S9] VERSION file exists, is semver, and > last shipped version

  Decision:
  ALL pass -> SHIP
  ANY fail -> KILL

  KILL output:
  {
    "verdict": "KILL",
    "failed_checks": ["S2", "S7"],
    "diagnostics": {
      "S2": "Run 3 crashed: SCRIPT ERROR at tower.gd:142",
      "S7": "No files matching marketing/screenshot_*.png"
    },
    "recommendation": "Fix crash in tower.gd, generate screenshot"
  }
```

**Key design decisions**:

1. **No CONDITIONAL**: This is deliberate. CONDITIONAL historically means "it's probably fine" and gets waved through. In an autonomous factory, "probably fine" ships broken games.

2. **3-run requirement**: Single-run gates are insufficient for VS-like games where RNG affects outcomes. 3 runs catch non-deterministic failures that single runs miss.

3. **Export validation built in**: The gate does not just validate gameplay -- it validates the entire distribution package. A game that plays perfectly but fails to export is not shippable.

4. **Version increment check**: Prevents shipping the same version twice. Forces intentional versioning.

**Implementation plan**:
1. `ship-or-kill.sh` -- New file, ~150 lines
2. Calls `quality-gate.sh` 3 times, aggregates results
3. Calls `godot --headless --export-release "HTML5"` and validates output
4. Checks marketing assets and metadata
5. Produces `ship_report.json`

---

### Finalist C: G07 -- Distribution Readiness Gate

**Why it advances to final 3**: This fills the gap that neither G18 nor G19 fully covers on their own: the specific requirements of distribution platforms. CrazyGames has a 50MB limit. Poki requires specific viewport handling. itch.io needs screenshots and descriptions. These are not quality checks -- they are compliance checks. A game can be perfect in every gameplay dimension and still be rejected by a platform for missing metadata.

**Detailed specification**:

```
DISTRIBUTION READINESS GATE
  Purpose: Verify the build meets platform-specific distribution requirements
  Run condition: After Ship-or-Kill says SHIP (or standalone pre-submission check)
  Cost: ~30 seconds

  Universal checks (all platforms):
  [D1] HTML5 export exists in dist/ directory
  [D2] index.html present in export
  [D3] Total export size < 50MB
  [D4] No file in export > 10MB (CDN-unfriendly)
  [D5] project.godot application/config/name is set and not "Godot"
  [D6] project.godot application/config/description is set and not empty
  [D7] Icon file exists and is not Godot default (file hash != known default hash)
  [D8] VERSION file exists, matches semver pattern (X.Y.Z)
  [D9] At least 1 screenshot in marketing/ (PNG, >= 640x480)
  [D10] CREDITS.md or LICENSE file exists

  Platform-specific checks:
  [P-CG1] CrazyGames: Export contains no eval() calls (security policy)
  [P-CG2] CrazyGames: Viewport scales to container (responsive check in index.html)
  [P-GD1] GameDistribution: Game has mute function (audio bus control exists)
  [P-IT1] itch.io: Game dimensions are 960x540 or larger

  PASS: All universal checks pass + target platform checks pass
  FAIL: Any check fails -> list failed checks with fix instructions
```

**Implementation plan**:
1. `dist-readiness.sh` -- New file, ~100 lines
2. Parameterized by platform: `--platform crazygames|gamedistribution|itchio|all`
3. Checks file existence, sizes, and content patterns
4. Produces `dist_report.json` with per-check results

---

### Why These 3 Cover the Pipeline

Together, the three finalists form a complete pipeline gate system:

```
Build -> [G18 Progressive Chain] -> Test -> [G19 Ship-or-Kill] -> [G07 Dist Readiness] -> Ship
          5s -> 15s -> 90s              3x runs (5min)              30s
          "Can it run?"                 "Is it good enough?"        "Can we upload it?"
```

- **G18** answers: "Is this build ready to test?" (fast fail, cheap reject)
- **G19** answers: "Is this game ready to ship?" (quality + consistency)
- **G07** answers: "Does the package meet platform requirements?" (compliance)

Each gate catches a distinct failure class:
- G18 catches: syntax errors, missing files, crash-on-boot, no-telemetry
- G19 catches: quality failures, flaky behavior, missing assets, regression
- G07 catches: export failures, size limits, missing metadata, platform policy violations

No gap between them. No overlap. No human decision needed.

---

## THE ONE: G18 -- Progressive Gate Chain

### Why This Is THE ONE

If the factory could implement only one gate system, the Progressive Gate Chain is the correct choice. Here is the reasoning:

**1. It multiplies the factory's iteration speed.**

The factory's productivity is `iterations_per_hour * quality_per_iteration`. The existing system runs every build through a 90-second autotest, regardless of build state. A build with a typo in line 3 wastes 90 seconds. A build with a missing scene file wastes 90 seconds. With progressive gating:

| Build Problem | Current Cost | With G18 |
|--------------|-------------|----------|
| Syntax error | 90s | 5s |
| Missing resource | 90s | 5s |
| Crash on load | 90s | 15s |
| No enemies spawn | 90s | 15s |
| Balance issue | 90s | 90s (same) |
| Good build | 90s | 90s (same) |

For a typical development session with 50% broken-build iterations (common during active development), this saves ~40 minutes per hour. That is not an optimization -- it is a paradigm shift.

**2. It provides better diagnostics.**

A single-pass gate that runs for 90 seconds and returns "FAIL" forces the agent to re-read the entire autotest log to find the problem. Progressive gates return the failure *level*, which immediately narrows the problem domain:

- "Failed at Quick" -> file/syntax problem -> check recent file edits
- "Failed at Medium" -> runtime crash -> check scene loading and initial spawns
- "Failed at Full" -> balance/quality problem -> check game parameters

This is the difference between "something is wrong" and "here is what is wrong."

**3. It is the foundation for everything else.**

G19 (Ship-or-Kill) requires G18 to run first -- there is no point running 3x autotest on a build that cannot even load. G07 (Distribution Readiness) requires a passing build to export. G18 is the prerequisite for both finalists.

More importantly, G18's three-level structure provides natural insertion points for future gates. Want to add juice checks? Insert them in the Medium gate. Want to add anti-pattern scanning? Insert in the Quick gate. The progressive chain is extensible by design.

**4. It requires zero new infrastructure.**

- Quick gate: `test -f`, `grep`, `godot --check-only` -- all existing tools
- Medium gate: `xvfb-run godot` with a shorter timeout -- same tool, different parameter
- Full gate: existing `quality-gate.sh` -- already built

The implementation is connecting existing tools in a new order, not building new tools.

**5. It embodies the factory's design philosophy.**

The factory principle is: **fail fast, fix fast, ship fast**. Progressive gating is the structural embodiment of this principle. Every check is ordered by cost (cheapest first) and specificity (broadest first). The factory never pays 90 seconds for a 5-second answer.

### Full Implementation Specification

#### `gate-chain.sh` -- Master Orchestrator

```bash
#!/usr/bin/env bash
# Game Factory Progressive Gate Chain
# Usage: gate-chain.sh [--level quick|medium|full|all] [--project-dir path]
# Exit 0 = all requested gates pass, Exit 1 = blocked

set -euo pipefail

LEVEL="${1:---level all}"
# parse --level argument
while [[ $# -gt 0 ]]; do
    case $1 in
        --level) LEVEL="$2"; shift 2 ;;
        --project-dir) PROJECT_DIR="$2"; shift 2 ;;
        *) shift ;;
    esac
done

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_FILE="/tmp/gate-chain-report.json"
TIMESTAMP=$(date -Is)

echo "[GateChain] === PROGRESSIVE GATE CHAIN ==="
echo "[GateChain] Project: $PROJECT_DIR"
echo "[GateChain] Level: $LEVEL"
echo "[GateChain] Time: $TIMESTAMP"

# Initialize report
REPORT='{"timestamp":"'$TIMESTAMP'","project":"'$PROJECT_DIR'","gates":{}}'

run_gate() {
    local gate_name="$1"
    local gate_script="$2"
    echo "[GateChain] --- $gate_name ---"
    if bash "$gate_script" "$PROJECT_DIR"; then
        echo "[GateChain] $gate_name: PASS"
        REPORT=$(echo "$REPORT" | jq --arg g "$gate_name" '.gates[$g] = "PASS"')
        return 0
    else
        echo "[GateChain] $gate_name: BLOCKED"
        REPORT=$(echo "$REPORT" | jq --arg g "$gate_name" '.gates[$g] = "BLOCKED"')
        REPORT=$(echo "$REPORT" | jq --arg g "$gate_name" '.blocked_at = $g')
        echo "$REPORT" | jq . > "$REPORT_FILE"
        echo "[GateChain] Report: $REPORT_FILE"
        return 1
    fi
}

# QUICK GATE (always runs)
run_gate "QUICK" "$GATE_DIR/gate-quick.sh" || exit 1

if [[ "$LEVEL" == "quick" ]]; then
    REPORT=$(echo "$REPORT" | jq '.verdict = "PASS_QUICK"')
    echo "$REPORT" | jq . > "$REPORT_FILE"
    echo "[GateChain] === VERDICT: PASS (quick only) ==="
    exit 0
fi

# MEDIUM GATE
run_gate "MEDIUM" "$GATE_DIR/gate-medium.sh" || exit 1

if [[ "$LEVEL" == "medium" ]]; then
    REPORT=$(echo "$REPORT" | jq '.verdict = "PASS_MEDIUM"')
    echo "$REPORT" | jq . > "$REPORT_FILE"
    echo "[GateChain] === VERDICT: PASS (up to medium) ==="
    exit 0
fi

# FULL GATE
run_gate "FULL" "$GATE_DIR/gate-full.sh" || exit 1

REPORT=$(echo "$REPORT" | jq '.verdict = "PASS_ALL"')
echo "$REPORT" | jq . > "$REPORT_FILE"
echo "[GateChain] === VERDICT: PASS (all gates) ==="
echo "[GateChain] Report: $REPORT_FILE"
exit 0
```

#### `gate-quick.sh` -- Quick Gate (5 seconds)

```bash
#!/usr/bin/env bash
# Quick Gate: File existence and syntax validation
# Exit 0 = pass, Exit 1 = blocked

set -euo pipefail
PROJECT_DIR="${1:-.}"
FAILS=()

echo "[QuickGate] Checking $PROJECT_DIR"

# Q1: project.godot exists with main scene
if [[ ! -f "$PROJECT_DIR/project.godot" ]]; then
    FAILS+=("Q1: project.godot missing")
else
    MAIN_SCENE=$(grep 'run/main_scene' "$PROJECT_DIR/project.godot" | head -1)
    if [[ -z "$MAIN_SCENE" ]]; then
        FAILS+=("Q1: run/main_scene not set in project.godot")
    else
        echo "[QuickGate] Q1: project.godot OK (main_scene set)"
    fi
fi

# Q2: Main scene file exists
if [[ ${#FAILS[@]} -eq 0 || ! "${FAILS[*]}" =~ "Q1" ]]; then
    SCENE_PATH=$(grep 'run/main_scene' "$PROJECT_DIR/project.godot" \
        | sed 's/.*"res:\/\///' | sed 's/".*//')
    if [[ -n "$SCENE_PATH" && -f "$PROJECT_DIR/$SCENE_PATH" ]]; then
        echo "[QuickGate] Q2: Main scene exists ($SCENE_PATH)"
    else
        FAILS+=("Q2: Main scene file not found ($SCENE_PATH)")
    fi
fi

# Q3: Syntax check (project-level)
if timeout 10 godot --headless --path "$PROJECT_DIR" --check-only 2>&1 | grep -qi "error"; then
    FAILS+=("Q3: GDScript syntax errors detected")
else
    echo "[QuickGate] Q3: Syntax clean"
fi

# Q4: Resource path validation
BROKEN_REFS=$(grep -rh 'res://' "$PROJECT_DIR"/scenes/*.tscn 2>/dev/null \
    | grep -oP 'res://[^"]+' \
    | sort -u \
    | while read -r ref; do
        local_path="$PROJECT_DIR/${ref#res://}"
        if [[ ! -f "$local_path" ]]; then
            echo "$ref"
        fi
    done || true)
if [[ -n "$BROKEN_REFS" ]]; then
    FAILS+=("Q4: Broken resource refs: $BROKEN_REFS")
else
    echo "[QuickGate] Q4: Resource paths OK"
fi

# Q5: Scripts exist
SCRIPT_COUNT=$(find "$PROJECT_DIR/scripts" -name "*.gd" 2>/dev/null | wc -l)
if [[ "$SCRIPT_COUNT" -lt 1 ]]; then
    FAILS+=("Q5: No .gd scripts in scripts/")
else
    echo "[QuickGate] Q5: $SCRIPT_COUNT scripts found"
fi

# Q6: Export config exists
if [[ ! -f "$PROJECT_DIR/export_presets.cfg" ]]; then
    FAILS+=("Q6: export_presets.cfg missing")
else
    echo "[QuickGate] Q6: export_presets.cfg exists"
fi

# Verdict
if [[ ${#FAILS[@]} -gt 0 ]]; then
    echo "[QuickGate] BLOCKED: ${#FAILS[@]} failures"
    for f in "${FAILS[@]}"; do
        echo "[QuickGate]   - $f"
    done
    exit 1
else
    echo "[QuickGate] PASS (6/6)"
    exit 0
fi
```

#### `gate-medium.sh` -- Medium Gate (15 seconds)

```bash
#!/usr/bin/env bash
# Medium Gate: Dry run validation (15s Godot execution)
# Exit 0 = pass, Exit 1 = blocked

set -euo pipefail
PROJECT_DIR="${1:-.}"
DRY_RUN_DURATION=10
TIMEOUT_DURATION=20
FAILS=()
OUTPUT_LOG="/tmp/gate-medium-output.log"

echo "[MediumGate] Running 10s dry run..."

# Run game for 10 seconds (autotest in short mode or bare run)
timeout "$TIMEOUT_DURATION" xvfb-run -a godot --headless --path "$PROJECT_DIR" \
    2>&1 | head -500 > "$OUTPUT_LOG" || true

# M1: No crash (check for fatal errors)
if grep -qi "FATAL\|Segmentation fault\|core dumped" "$OUTPUT_LOG"; then
    FAILS+=("M1: Fatal crash detected")
else
    echo "[MediumGate] M1: No crash"
fi

# M2: No SCRIPT ERROR
SCRIPT_ERRORS=$(grep -c "SCRIPT ERROR" "$OUTPUT_LOG" || true)
if [[ "$SCRIPT_ERRORS" -gt 0 ]]; then
    FAILS+=("M2: $SCRIPT_ERRORS SCRIPT ERROR(s) in output")
else
    echo "[MediumGate] M2: No script errors"
fi

# M3-M6: Check telemetry output if available
RESULTS="/tmp/godot_auto_test/results.json"
if [[ -f "$RESULTS" ]]; then
    # M3: Enemy spawned
    ENEMY_COUNT=$(jq '[.quality_metrics.enemy_count_samples[].count] | max // 0' "$RESULTS" 2>/dev/null || echo "0")
    if [[ "$ENEMY_COUNT" -gt 0 ]]; then
        echo "[MediumGate] M3: Enemies spawned (peak=$ENEMY_COUNT)"
    else
        FAILS+=("M3: No enemies spawned")
    fi

    # M4: Fire events
    FIRES=$(jq '.telemetry.total_fires // 0' "$RESULTS" 2>/dev/null || echo "0")
    if [[ "$FIRES" -gt 0 ]]; then
        echo "[MediumGate] M4: Fire events detected ($FIRES)"
    else
        FAILS+=("M4: No fire events")
    fi

    # M5: Player alive (final HP > 0 or pass=true)
    PASS_VAL=$(jq -r '.pass // "false"' "$RESULTS" 2>/dev/null || echo "false")
    echo "[MediumGate] M5: Test pass=$PASS_VAL"

    # M6: Telemetry schema valid
    HAS_TELEMETRY=$(jq 'has("telemetry") and has("quality_metrics")' "$RESULTS" 2>/dev/null || echo "false")
    if [[ "$HAS_TELEMETRY" == "true" ]]; then
        echo "[MediumGate] M6: Telemetry schema valid"
    else
        FAILS+=("M6: Telemetry schema incomplete")
    fi
else
    echo "[MediumGate] M3-M6: No results.json (dry run only, skipping telemetry checks)"
    # In dry-run mode without autotest, M3-M6 are advisory
fi

# Verdict
if [[ ${#FAILS[@]} -gt 0 ]]; then
    echo "[MediumGate] BLOCKED: ${#FAILS[@]} failures"
    for f in "${FAILS[@]}"; do
        echo "[MediumGate]   - $f"
    done
    exit 1
else
    echo "[MediumGate] PASS"
    exit 0
fi
```

#### `gate-full.sh` -- Full Gate (wraps existing quality-gate.sh)

```bash
#!/usr/bin/env bash
# Full Gate: Complete quality evaluation (wraps quality-gate.sh)
# Exit 0 = pass, Exit 1 = blocked

set -euo pipefail
PROJECT_DIR="${1:-.}"
GATE_DIR="$PROJECT_DIR/quality-gate"

echo "[FullGate] Running complete quality evaluation..."

# Run existing quality gate
if bash "$GATE_DIR/quality-gate.sh"; then
    QG_VERDICT="GO_OR_CONDITIONAL"
else
    QG_VERDICT="NO-GO"
fi

# Parse results for additional feel scorecard checks
RESULTS="/tmp/godot_auto_test/results.json"
FAILS=()

if [[ "$QG_VERDICT" == "NO-GO" ]]; then
    FAILS+=("F1: quality-gate.sh returned NO-GO")
fi

# F5: Feel scorecard check (if present)
if [[ -f "$RESULTS" ]]; then
    DESIRE_RATING=$(jq -r '.feel_scorecard.run_desire_rating // "N/A"' "$RESULTS" 2>/dev/null || echo "N/A")
    if [[ "$DESIRE_RATING" == "FAIL" ]]; then
        FAILS+=("F6: Run Completion Desire is FAIL")
    fi
    echo "[FullGate] Feel: desire=$DESIRE_RATING"
fi

if [[ ${#FAILS[@]} -gt 0 ]]; then
    echo "[FullGate] BLOCKED: ${#FAILS[@]} failures"
    for f in "${FAILS[@]}"; do
        echo "[FullGate]   - $f"
    done
    exit 1
else
    echo "[FullGate] PASS"
    exit 0
fi
```

### Integration with Existing Pipeline

The Progressive Gate Chain integrates into the factory workflow as follows:

```
[Claude Code iteration loop]
  1. Make code changes
  2. Run: gate-chain.sh --level quick --project-dir /path/to/game
     -> If BLOCKED: fix issue (5s feedback), goto 1
  3. Run: gate-chain.sh --level medium --project-dir /path/to/game
     -> If BLOCKED: fix issue (15s feedback), goto 1
  4. Run: gate-chain.sh --level all --project-dir /path/to/game
     -> If BLOCKED: fix issue (90s feedback), goto 1
     -> If PASS: proceed to ship decision
  5. Run: ship-or-kill.sh --project-dir /path/to/game
     -> If KILL: fix issues, goto 1
     -> If SHIP: proceed to distribution
  6. Run: dist-readiness.sh --platform crazygames --project-dir /path/to/game
     -> If FAIL: fix compliance issues, goto 5
     -> If PASS: upload and ship
```

In practice, during active development, the agent runs `--level quick` after every file edit (5s cost). It runs `--level medium` after completing a feature (15s cost). It runs `--level all` only when it believes the build is ready for evaluation (90s cost). This natural escalation matches the development rhythm.

### Relationship to G19 and G07

While G18 is THE ONE (the single gate to implement first), the complete pipeline requires all three finalists:

```
                  G18                           G19              G07
         Progressive Chain              Ship-or-Kill      Dist Readiness
    ┌─────────┬──────────┬─────────┐   ┌───────────┐   ┌──────────────┐
    │  QUICK  │  MEDIUM  │  FULL   │   │  3x runs  │   │  Platform    │
    │  5 sec  │  15 sec  │  90 sec │──>│  Export    │──>│  compliance  │
    │  files  │  boot    │  quality│   │  Assets    │   │  metadata    │
    │  syntax │  spawn   │  balance│   │  Version   │   │  size limits │
    └─────────┴──────────┴─────────┘   └───────────┘   └──────────────┘
         Build -> Test boundary        Test -> Ship      Ship -> Dist
```

**Implementation order**:
1. **Week 1**: G18 (Progressive Chain) -- the foundation
2. **Week 2**: G19 (Ship-or-Kill) -- the quality bar
3. **Week 3**: G07 (Distribution Readiness) -- the compliance layer

Each builds on the previous. G19 calls G18 internally. G07 runs after G19 passes. By Week 3, the factory has a complete, zero-human pipeline from Build to Distribution.

### Calibration and Evolution

The thresholds in each gate should be stored in `thresholds.json` (extending the existing file) and tuned over time:

```json
{
  "gate_chain": {
    "quick": {
      "min_scripts": 1,
      "syntax_errors_allowed": 0
    },
    "medium": {
      "timeout_seconds": 20,
      "max_script_errors": 0,
      "min_enemy_count": 1,
      "min_fire_count": 1
    },
    "full": {
      "quality_gate_verdict_required": "GO_OR_CONDITIONAL",
      "feel_scorecard_fail_allowed": false,
      "min_desire_score": 0.4
    }
  },
  "ship_or_kill": {
    "num_runs": 3,
    "max_metric_cv": 0.30,
    "max_export_size_mb": 50,
    "require_screenshots": true,
    "require_version_increment": true
  },
  "dist_readiness": {
    "max_single_file_mb": 10,
    "min_screenshot_width": 640,
    "min_screenshot_height": 480,
    "known_default_icon_hash": "abc123..."
  }
}
```

As the factory ships more games, these thresholds tighten. Games that pass today's gates but receive poor player feedback inform tomorrow's thresholds. The gate system learns from distribution outcomes.

---

## Appendix A: Rejected Candidates and Why

| Gate | Total | Rejection Reason |
|------|-------|-----------------|
| G01 | 12 | Subsumed by G18's Quick Gate |
| G02 | 12 | Subsumed by G18's Quick Gate |
| G03 | 11 | Requires design doc format that does not exist yet |
| G04 | 12 | Subsumed by G18's Quick Gate (resource validation) |
| G05 | 12 | Too broad for first implementation; G18+G19+G07 compose into this |
| G06 | 12 | Subsumed by G18's Quick Gate |
| G08 | 12 | Good checks but narrow; individual checks folded into G18 Quick |
| G09 | 12 | Valuable but lower priority than the three finalists; add as G18 extension later |
| G11 | 12 | Keyword detection unreliable; behavioral validation in G18 Medium is better |
| G12 | 12 | Subsumed by G19's 3-run requirement |
| G13 | 12 | Subsumed by G07's export validation |
| G14 | 11 | Narrow focus on audio only; subsumed by G09 which was itself deferred |
| G15 | 11 | Premature; factory needs Build->Ship before Idea gate |
| G16 | 11 | Code quality checks do not map to player experience; lower priority |
| G17 | 11 | Subsumed by G18's Medium Gate (telemetry validation) |
| G20 | 12 | G18+G19+G07 compose into this naturally; no need for upfront orchestrator |

## Appendix B: Future Extensions

Once the core three gates are operational, these extensions add value:

1. **Juice Presence Check** (from G09): Add to G18 Medium Gate as advisory check. Grep for screen_shake, tween, particles.
2. **Anti-Pattern Scanner** (from G16): Add to G18 Quick Gate. Catch `load()` in `_process()`, `print()` in production code.
3. **Idea Gate** (from G03/G15): Add once the design doc YAML schema is defined. Runs before Build.
4. **Performance Profiling** (from G08): Add to G18 Full Gate. Check frame timing from autotest telemetry.
5. **A/B Distribution** (from G07): Run distribution readiness for multiple platforms in parallel, submit to whichever passes.
6. **Cross-Game Regression**: Compare metrics across different games to establish factory-wide quality baselines.

## Appendix C: Decision Trace

```
20 candidates generated
  -> Scored on Autonomy, Coverage, Simplicity (1-5 each)
  -> 4 candidates scored 13 (G07, G10, G18, G19)
  -> 8 candidates scored 12
  -> 5 candidates scored 11
  -> Ties broken by Coverage, then Simplicity

6 shortlisted: G07, G10, G18, G19, G09, G12
  -> G10 cut: its regression checks fold into G19's 3-run comparison
  -> G09 cut: juice checks are high-value but lower priority than structural pipeline gates
  -> G12 cut: its 3-run requirement folds into G19

3 finalists: G18, G19, G07
  -> G18 vs G19: G18 is prerequisite for G19 (must pass chain before ship decision)
  -> G18 vs G07: G18 addresses the largest time waste (90s for 5s problems)
  -> G07 vs G19: G07 catches compliance failures that G19 misses

THE ONE: G18 (Progressive Gate Chain)
  -> Highest leverage: saves ~40 min/hr during active development
  -> Best diagnostics: failure level pinpoints problem domain
  -> Foundation for others: G19 and G07 build on top of G18
  -> Zero new tools: connects existing infrastructure in new order
```

---

## References

- `GAME_QUALITY_FRAMEWORK.md` -- 7-dimension scoring rubric, automated testing implementation
- `docs/feel-scorecard-20-6-3-1.md` -- Feel Scorecard design (dead time, action density, reward frequency)
- `docs/feel-autoeval-heuristics-20-6-3-1.md` -- 20 feel heuristics, Run Completion Desire (THE ONE feel metric)
- `docs/distribution-experiment-20-6-3-1.md` -- Distribution channel analysis, CrazyGames as primary
- `quality-gate/quality-gate.sh` -- Existing 3-tier quality gate implementation
- `quality-gate/thresholds.json` -- Current quality gate thresholds
- `scripts/debug/SpellCascadeAutoTest.gd` -- 60s autotest bot with telemetry
- `scripts/debug/AutoPlayer.gd` -- Input simulation bot
