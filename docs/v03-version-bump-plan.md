# v0.3.0 Version Bump Plan
Date: 2026-02-16
Task: explore-spell-cascade-v03-version-bump-plan

## What's New in v0.3.0

### Sound System (5 new procedural sounds)
- **BGM**: 8s dark ambient loop (Am: bass drone + arpeggio + pad harmonics + LFO)
- **Boss Entrance**: Low rumble + metallic ring + downward sweep
- **Wave Clear**: Ascending 5-note fanfare (C5→D5→E5→G5→C6)
- **UI Cancel**: Descending blip on ESC/pause
- **Player Damage Taken**: Metallic crunch with 150ms cooldown

### Quality Infrastructure
- **Autonomous Quality Gate**: 3-tier GO/NO-GO judgment (stability → balance → regression)
- **Feel Scorecard**: Dead Time, Action Density, Reward Frequency metrics
- **Autoplay Metrics Harness**: Automated testing with feel measurement
- **Baseline System**: JSON baselines for regression detection

### Design Documents (20→6→3→1 framework)
- Sound feedback loop design
- Distribution experiment (CrazyGames / Newgrounds / GameDistribution)
- Reward curve & stage transition design
- Feel scorecard methodology

## Version Bump Checklist

### Essential Files (4 files, must update)

| # | File | Line | Current | New |
|---|------|------|---------|-----|
| 1 | `VERSION` | 1 | `0.2.2` | `0.3.0` |
| 2 | `README.md` | 55 | `v0.2.2` | `v0.3.0` |
| 3 | `CREDITS.md` | 3 | `v0.1.0` | `v0.3.0` |
| 4 | `marketing/presskit.md` | 13 | `v0.2.2` | `v0.3.0` |

### Recommended Updates (runbooks, update artifact paths)

| # | File | Action |
|---|------|--------|
| 5 | `ops/runbooks/itch-upload-v0.md` | Update artifact path to v0.3.0 |
| 6 | `ops/infra/spell-cascade-gh-release-draft-2026-02-16.md` | Create new v0.3.0 release draft |

### Post-Bump Actions

| # | Action | Command |
|---|--------|---------|
| 7 | Git tag | `git tag v0.3.0` |
| 8 | Re-export HTML5 | Godot export with updated version |
| 9 | Re-export Windows | Godot export with updated version |
| 10 | Update itch.io page | Upload new builds |
| 11 | Update quality gate baseline | Run gate, save new latest.json |

### Files NOT Requiring Changes (confirmed)

- `project.godot` — `config_version=5` is Godot engine version, not app version
- `export_presets.cfg` — No app version fields populated
- GDScript files — No version constants (only historical comments)
- `docs/*.md` — Historical references, keep as-is for context

## Changelog Draft (v0.3.0)

```markdown
## v0.3.0 — Sound & Quality (2026-02-16)

### Added
- Procedural BGM: 8-second dark ambient loop
- Boss entrance sound effect (low rumble + metallic ring)
- Wave clear fanfare on boss defeat and milestones
- UI cancel sound on pause (ESC)
- Player damage taken metallic crunch (150ms cooldown)
- Autonomous 3-tier quality gate (GO/CONDITIONAL/NO-GO)
- Feel scorecard: Dead Time, Action Density, Reward Frequency
- Autoplay metrics harness with baseline regression detection
- v0.2.5 feel scorecard baseline

### Fixed
- Quality gate --quit-after: was counting frames, not seconds
- Web export size: pck reduced 3.3MB → 282KB (excluded marketing/debug)

### Design
- Reward curve & stage transition analysis (20→6→3→1)
- Sound feedback loop prioritization
- Distribution channel readiness assessments (CrazyGames, Newgrounds, GameDistribution)
- Feel scorecard methodology document
```

## Execution Order

1. Update 4 essential files (VERSION, README, CREDITS, presskit)
2. Run quality gate to verify nothing broke
3. Git commit: "Bump version to v0.3.0"
4. Git tag: `v0.3.0`
5. Re-export builds (HTML5 + Windows)
6. Update itch.io (new builds + changelog in devlog)
7. Update quality gate baseline with v0.3.0 data

## Blockers

- **None for version bump itself** — pure metadata change
- **itch.io upload**: Requires human approval (external/public action)
- **New builds**: Require Godot export (automated via export_presets.cfg)

## Pre-Bump Consideration

The reward curve design recommends XP threshold rebalance (+35%) as the next build task. Decision point:
- **Option A**: Bump to v0.3.0 now (sound-only release), XP rebalance goes into v0.3.1
- **Option B**: Include XP rebalance in v0.3.0 for a more impactful release

Recommendation: **Option A** — ship what's done, iterate fast. Sound system is already validated by quality gate.
