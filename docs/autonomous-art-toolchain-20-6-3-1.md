# Autonomous Art Toolchain: 20 → 6 → 3 → 1

Date: 2026-02-16
Context: Game Factory — autonomous game production pipeline. Art is the #1 visual bottleneck.
Constraint: **Recurring human touch: NO**. Every tool must be fully automatable by CC via API/CLI/MCP.

## Problem Statement

Spell Cascade uses programmer art (shader-drawn shapes, procedural Pillow sprites). This is the biggest barrier to:
1. **Distribution acceptance** — CrazyGames/Newgrounds evaluate visual quality
2. **Player retention** — first impression is visual
3. **Factory scalability** — can't ship multiple games if each needs hand-drawn art

The factory needs an **art toolchain** that CC can operate autonomously, producing pixel art sprites, animations, and tilesets at a quality level above programmer art.

### Current State

| Asset Type | Current Tool | Quality Level |
|------------|-------------|---------------|
| Characters/enemies | gen_sprite.py (Pillow symmetric noise) | 2/10 — recognizable but ugly |
| Projectiles | gen_sprite.py (radial gradient) | 3/10 — functional |
| Effects | Godot shader in-code | 4/10 — decent for particles |
| UI icons | gen_sprite.py (bordered fill) | 2/10 — placeholder tier |
| Tilesets | None | 0/10 — no tileset system |
| Animation | None | 0/10 — static sprites only |

### Scoring Axes (1-5 each, max 15)

- **Quality (Q)**: Output pixel art quality for VS-like games. 5=hand-drawn tier, 1=colored noise
- **Autonomy (A)**: Can CC run it without human? 5=API/CLI, no setup; 1=GUI required
- **Cost-Efficiency (CE)**: Bang for buck. 5=free or <$5/mo; 1=>$50/mo

---

## The 20 Candidates

### T01: gen_sprite.py (current — Pillow + NumPy)
- **Type**: Procedural generation
- **Cost**: Free (installed)
- **API/CLI**: Python CLI, full control
- **Q**: 2 — symmetric noise blobs. Recognizable shapes but not appealing
- **A**: 5 — fully autonomous, already working
- **CE**: 5 — zero cost

| Q | A | CE | Total |
|---|---|----|----|
| 2 | 5 | 5 | 12 |

---

### T02: PixelLab MCP Server
- **Type**: AI pixel art generation
- **Cost**: $24/mo (Pixel Artisan tier), 40 free trial credits
- **API/CLI**: MCP Server (pixellab-code/pixellab-mcp). Text prompt → sprite
- **Q**: 5 — purpose-built for pixel art. Characters, animations, tilesets
- **A**: 5 — MCP Server plugs into CC directly, no human step
- **CE**: 3 — $24/mo recurring, but high value per generation

| Q | A | CE | Total |
|---|---|----|----|
| 5 | 5 | 3 | 13 |

---

### T03: Retro Diffusion (via Replicate API)
- **Type**: AI pixel art generation (specialized SD model)
- **Cost**: ~$0.01-0.05/image (pay per use)
- **API/CLI**: Replicate HTTP API. 3 models: rd-fast, rd-plus, rd-animation
- **Q**: 4 — good pixel art style, grid-aligned output, palette-limited
- **A**: 5 — HTTP API, CC can call directly
- **CE**: 4 — pay-per-use scales well. ~$5 for 100-500 sprites

| Q | A | CE | Total |
|---|---|----|----|
| 4 | 5 | 4 | 13 |

---

### T04: Aseprite + pixel-mcp
- **Type**: Pixel art editor with CLI batch mode + MCP server
- **Cost**: $20 one-time (Steam)
- **API/CLI**: `aseprite -b` CLI + pixel-mcp (40+ MCP tools)
- **Q**: 4 — not a generator, but transforms/processes existing art. Spritesheet export, palette management, animation
- **A**: 5 — CLI batch mode + MCP means full autonomy
- **CE**: 5 — $20 one-time, massive feature set

| Q | A | CE | Total |
|---|---|----|----|
| 4 | 5 | 5 | 14 |

**Note**: Aseprite is a *processor*, not a *generator*. Best combined with a generator (T02/T03).

---

### T05: ImageMagick
- **Type**: CLI image manipulation
- **Cost**: Free (apt install)
- **API/CLI**: Full CLI (`convert`, `montage`, `composite`)
- **Q**: 2 — can process sprites (resize, palette-swap, spritesheet pack) but doesn't generate art
- **A**: 5 — CLI, no GUI
- **CE**: 5 — free

| Q | A | CE | Total |
|---|---|----|----|
| 2 | 5 | 5 | 12 |

---

### T06: Kenney.nl CC0 Asset Packs
- **Type**: Pre-made CC0 asset library
- **Cost**: Free (CC0 license)
- **API/CLI**: wget/curl download. 700+ packs on kenney.nl
- **Q**: 4 — professional, consistent style. But generic, not custom
- **A**: 5 — download and use, no human needed
- **CE**: 5 — free, CC0

| Q | A | CE | Total |
|---|---|----|----|
| 4 | 5 | 5 | 14 |

**Limitation**: Fixed assets, can't generate custom designs. Style may not match between packs.

---

### T07: OpenGameArt.org CC0 Assets
- **Type**: Community CC0/CC-BY asset repository
- **Cost**: Free
- **API/CLI**: wget download (no API, but can scrape URLs)
- **Q**: 3 — quality varies wildly. Some excellent, some amateur
- **A**: 4 — downloadable but no structured API. Requires manual URL discovery
- **CE**: 5 — free

| Q | A | CE | Total |
|---|---|----|----|
| 3 | 4 | 5 | 12 |

---

### T08: Universal LPC Spritesheet Generator
- **Type**: Character spritesheet assembler (mix-and-match layers)
- **Cost**: Free (CC-BY-SA/GPL)
- **API/CLI**: Web-only generator. GitHub repo has raw assets. Godot plugin exists
- **Q**: 4 — consistent RPG style, good for top-down characters
- **A**: 3 — web UI primary. Could automate via the raw PNG layers + Python assembly
- **CE**: 5 — free

| Q | A | CE | Total |
|---|---|----|----|
| 4 | 3 | 5 | 12 |

---

### T09: pixel-sprite-generator (JS/Python)
- **Type**: Procedural symmetric sprite generation (like gen_sprite.py but more refined)
- **Cost**: Free (npm/pip)
- **API/CLI**: Node.js module or Python port
- **Q**: 3 — symmetric pixel sprites with masks. Better than random noise
- **A**: 5 — library call, fully autonomous
- **CE**: 5 — free

| Q | A | CE | Total |
|---|---|----|----|
| 3 | 5 | 5 | 13 |

---

### T10: Pillow + Perlin Noise (noise library)
- **Type**: Procedural texture/pattern generation
- **Cost**: Free (pip install noise)
- **API/CLI**: Python library
- **Q**: 2 — generates noise patterns, not recognizable sprites. Good for terrain/backgrounds
- **A**: 5 — Python library
- **CE**: 5 — free

| Q | A | CE | Total |
|---|---|----|----|
| 2 | 5 | 5 | 12 |

---

### T11: DALL-E 3 API (pixel art prompt)
- **Type**: General-purpose AI image generation with pixel art prompts
- **Cost**: $0.04-0.12/image (OpenAI API)
- **API/CLI**: REST API
- **Q**: 3 — can produce pixel-art-like images but not pixel-perfect. Often too high-res
- **A**: 5 — API call
- **CE**: 3 — more expensive per image than specialized tools

| Q | A | CE | Total |
|---|---|----|----|
| 3 | 5 | 3 | 11 |

---

### T12: Stable Diffusion (local) with pixel art LoRA
- **Type**: Local AI image generation
- **Cost**: Free (model weights)
- **API/CLI**: ComfyUI API or diffusers Python library
- **Q**: 4 — with proper LoRA, good pixel art output
- **A**: 2 — requires GPU. WSL2 environment has no GPU. Would need cloud GPU
- **CE**: 2 — cloud GPU costs ($0.50+/hr) or doesn't run locally

| Q | A | CE | Total |
|---|---|----|----|
| 4 | 2 | 2 | 8 |

---

### T13: Stable Diffusion via Replicate (generic)
- **Type**: Cloud AI image generation
- **Cost**: ~$0.01-0.05/image
- **API/CLI**: Replicate HTTP API
- **Q**: 3 — generic SD models need careful prompting for pixel art
- **A**: 5 — API call
- **CE**: 4 — pay per use

| Q | A | CE | Total |
|---|---|----|----|
| 3 | 5 | 4 | 12 |

---

### T14: Google AI Studio (Gemini image generation)
- **Type**: AI image generation via browser automation
- **Cost**: Free (browser-based)
- **API/CLI**: CDP browser automation (ai-studio skill exists)
- **Q**: 3 — general-purpose, not pixel-art specialized
- **A**: 3 — works via CDP but requires browser automation, fragile
- **CE**: 5 — free

| Q | A | CE | Total |
|---|---|----|----|
| 3 | 3 | 5 | 11 |

---

### T15: GraphicsMagick
- **Type**: CLI image processing (ImageMagick fork, lighter)
- **Cost**: Free
- **API/CLI**: Full CLI
- **Q**: 2 — processing only, no generation
- **A**: 5 — CLI
- **CE**: 5 — free

| Q | A | CE | Total |
|---|---|----|----|
| 2 | 5 | 5 | 12 |

---

### T16: Piskel (Open Source Pixel Editor)
- **Type**: Web-based pixel art editor
- **Cost**: Free
- **API/CLI**: Web UI only. No CLI or API
- **Q**: N/A — editor, not generator
- **A**: 1 — GUI only, no automation path
- **CE**: 5 — free

| Q | A | CE | Total |
|---|---|----|----|
| N/A | 1 | 5 | 6 |

**Eliminated**: No CLI/API = cannot automate.

---

### T17: PixelOver
- **Type**: Convert art to pixel art + animation
- **Cost**: $25 (Steam)
- **API/CLI**: GUI only as of 2022 (no CLI confirmed)
- **Q**: 4 — converts high-res art to pixel art with good results
- **A**: 1 — GUI only
- **CE**: 4 — one-time cost

| Q | A | CE | Total |
|---|---|----|----|
| 4 | 1 | 4 | 9 |

**Eliminated**: No CLI.

---

### T18: Godot Shader-Based Sprite Generation
- **Type**: In-engine procedural generation via shaders
- **Cost**: Free (already available)
- **API/CLI**: GDScript + shader code, controllable via godot-mcp
- **Q**: 3 — can create decent effects, particles. Characters are hard
- **A**: 5 — fully in-engine, CC controls via GDScript
- **CE**: 5 — free

| Q | A | CE | Total |
|---|---|----|----|
| 3 | 5 | 5 | 13 |

---

### T19: Wave Function Collapse (wfc) for Tilesets
- **Type**: Procedural tilemap generation algorithm
- **Cost**: Free (multiple Python implementations)
- **API/CLI**: Python library
- **Q**: 3 — generates tilemap layouts from sample tiles. Needs source tiles
- **A**: 5 — Python library
- **CE**: 5 — free

| Q | A | CE | Total |
|---|---|----|----|
| 3 | 5 | 5 | 13 |

---

### T20: Composite Pipeline (gen_sprite.py + ImageMagick + palette scripts)
- **Type**: Multi-tool pipeline — generate → process → assemble
- **Cost**: Free (all tools installed or installable)
- **API/CLI**: Shell pipeline
- **Q**: 3 — better than any single free tool via multi-pass processing
- **A**: 5 — shell script
- **CE**: 5 — free

| Q | A | CE | Total |
|---|---|----|----|
| 3 | 5 | 5 | 13 |

---

## Ranking: 20 → 6

Sorted by total score, with hard elimination for A < 3 (not automatable):

| Rank | Tool | Q | A | CE | Total | Notes |
|------|------|---|---|----|----|-------|
| 1 | **T04: Aseprite + pixel-mcp** | 4 | 5 | 5 | **14** | Processor, not generator |
| 2 | **T06: Kenney CC0 Packs** | 4 | 5 | 5 | **14** | Fixed assets |
| 3 | **T02: PixelLab MCP** | 5 | 5 | 3 | **13** | Best quality, costs money |
| 4 | **T03: Retro Diffusion** | 4 | 5 | 4 | **13** | Pay-per-use AI |
| 5 | **T09: pixel-sprite-generator** | 3 | 5 | 5 | **13** | Free procedural |
| 6 | **T18: Godot Shaders** | 3 | 5 | 5 | **13** | In-engine |
| ---|------|---|---|----|----|-------|
| 7 | T19: WFC | 3 | 5 | 5 | 13 | Tilemap-specific |
| 8 | T20: Composite Pipeline | 3 | 5 | 5 | 13 | Multi-tool |
| 9 | T01: gen_sprite.py | 2 | 5 | 5 | 12 | Current, lowest quality |

**Eliminated** (A < 3): T16 Piskel (A=1), T17 PixelOver (A=1), T12 Local SD (A=2)
**Below cut**: T11 DALL-E (11), T14 AI Studio (11)

## The 6 Finalists

1. **T04: Aseprite + pixel-mcp** — Post-processing powerhouse
2. **T06: Kenney CC0 Packs** — Instant quality, zero cost
3. **T02: PixelLab MCP** — Highest quality generation
4. **T03: Retro Diffusion** — Flexible pay-per-use AI
5. **T09: pixel-sprite-generator** — Free procedural upgrade
6. **T18: Godot Shaders** — Zero-dependency in-engine

---

## The 6 → 3 Narrowing

### Elimination Criteria

The factory needs a **complete art pipeline**, not just one tool. The 3 finalists should cover:
- **Generation** — creating new sprites from nothing
- **Processing** — transforming/animating/sheeting sprites
- **Baseline assets** — existing quality art to bootstrap with

### Analysis

| Tool | Generation | Processing | Baseline | Pipeline Role |
|------|-----------|-----------|----------|---------------|
| T04 Aseprite | No | **Yes** (best) | No | Post-processor |
| T06 Kenney | No | No | **Yes** (best) | Asset library |
| T02 PixelLab | **Yes** (best) | No | No | Generator |
| T03 Retro Diffusion | Yes (good) | No | No | Generator |
| T09 pixel-sprite-gen | Yes (basic) | No | No | Generator |
| T18 Godot Shaders | Yes (limited) | Yes (limited) | No | In-engine |

**Cut**:
- **T09 pixel-sprite-generator**: Dominated by T02/T03 for generation quality. Only advantage is "free," but gen_sprite.py already fills that role
- **T18 Godot Shaders**: Good for effects/particles but doesn't solve the character/enemy art problem. Already in use for what it does well

### The 3 Finalists

| Role | Tool | Why |
|------|------|-----|
| **Generator** | T02: PixelLab MCP | Highest quality. Purpose-built for pixel art. MCP = zero-friction integration |
| **Processor** | T04: Aseprite + pixel-mcp | CLI batch + 40 MCP tools. Spritesheet export, animation, palette management |
| **Baseline** | T06: Kenney CC0 Packs | 700+ packs, professional quality, zero cost. Instant visual upgrade |

---

## THE ONE: T06 — Kenney CC0 Asset Packs

### Why This Is THE ONE

If the factory could adopt only one art tool TODAY, it should be **Kenney CC0 Asset Packs**:

1. **Zero cost, zero risk**: No purchase approval needed. Download and use immediately
2. **Zero setup**: wget → unzip → copy to res://. No API keys, no subscriptions, no MCP config
3. **Instant quality upgrade**: From 2/10 programmer art to 4/10 professional pixel art TODAY
4. **CC0 license**: No attribution required, commercial use OK, no legal concerns
5. **Large variety**: 700+ packs covering characters, enemies, effects, UI, backgrounds, fonts
6. **Consistent style**: Packs within the same collection share visual consistency
7. **Spritesheet format**: Most come as spritesheets ready for Godot import

### Limitation Acknowledged

Kenney packs are **fixed assets** — you can't generate custom designs. But for the factory's current needs (ship VS-like games with decent visuals), having 100 professional sprites is infinitely better than having 10 procedural blobs. Custom generation (PixelLab/Retro Diffusion) is the Phase 2 upgrade.

### Implementation Plan (Today, ~30 minutes)

```bash
# 1. Download Kenney's top-down shooter pack (ideal for VS-like games)
mkdir -p assets/sprites/kenney
wget https://kenney.nl/media/pages/assets/tiny-dungeon/... -O /tmp/kenney-tiny-dungeon.zip
unzip /tmp/kenney-tiny-dungeon.zip -d assets/sprites/kenney/

# 2. Download Kenney's pixel platformer pack (for additional variety)
wget https://kenney.nl/media/pages/assets/pixel-shmup/... -O /tmp/kenney-pixel-shmup.zip
unzip /tmp/kenney-pixel-shmup.zip -d assets/sprites/kenney/

# 3. Godot import: copy PNGs to res://assets/sprites/kenney/
#    Godot auto-imports on next scan
```

### Upgrade Path

```
Phase 1 (NOW):     Kenney CC0 packs → immediate visual upgrade
Phase 2 (Week 2):  PixelLab MCP free trial → test custom generation quality
Phase 3 (Week 3):  Aseprite CLI → process PixelLab output into spritesheets
Phase 4 (Month 2): Full pipeline: PixelLab→Aseprite→Godot, all via MCP/CLI
```

### Decision Matrix Summary

| Criterion | T02 PixelLab | T04 Aseprite | T06 Kenney |
|-----------|-------------|-------------|------------|
| Cost now | $24/mo (needs approval) | $20 (needs approval) | **Free** |
| Time to first sprite | ~1 hour (setup MCP) | ~30 min (install + config) | **~5 min** (download) |
| Quality ceiling | **5/10** | 4/10 (processing) | 4/10 (fixed) |
| Approval needed | Yes | Yes | **No** |
| Customizability | **High** | Medium | Low |

**For the factory RIGHT NOW**: Kenney wins because it requires zero human approval, zero setup time, and provides an instant quality jump. The factory's bottleneck isn't "custom art" — it's "any decent art at all."

---

## Relationship Between The 3

The complete art pipeline uses all three:

```
Kenney CC0 → Baseline sprites (immediate)
    ↓
PixelLab MCP → Custom sprites for unique game elements (pending approval)
    ↓
Aseprite CLI → Post-process all sprites (spritesheet, animation, palette) (pending approval)
    ↓
gen_sprite.py + ImageMagick → Fallback procedural for simple shapes
    ↓
Godot import → res:// → game
```

---

*Generated by Game Factory Pipeline — Art Toolchain Analysis v1*
