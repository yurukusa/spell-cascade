# v0.4 Art Direction Lock v2 — 20→6→3→1

**Date**: 2026-02-16
**Task**: explore-v04-art-direction-lock-v2-20-6-3-1
**Context**: Spell Cascade currently uses shader-drawn geometric shapes (circles, diamonds, hexagons) with a locked semantic color palette. 7 Kenney CC0 packs are downloaded but unused in-game. v0.3 focused on sound and balance. v0.4 must decide the visual identity going forward.

**Constraint**: Threat readability must not degrade. The 4-tier visual hierarchy (BG 0.2 → Collision 0.5 → Interactive 0.7 → Threat 1.0) is non-negotiable.

---

## Problem Statement

The game has two conflicting signals:
1. **README says "Placeholder visuals (geometric shapes)"** — implying shapes are temporary
2. **art_config.json is status=locked** — implying shapes are an intentional design system

The question: Is the geometric style a placeholder to replace, or a visual identity to refine?

This decision cascades into everything: what art pipeline to build, how to position on storefronts, what marketing screenshots look like, and whether future games in the factory share a visual identity.

---

## Scoring Axes (1-5 each, max 20)

- **D (Distinctiveness)**: Does this direction stand out in the VS-like market?
- **R (Readability)**: How well can players parse gameplay at a glance?
- **F (Feasibility)**: Can CC implement this autonomously? (5=fully autonomous, 1=needs artist)
- **S (Scalability)**: Can this direction work across multiple factory games?

---

## 20 Candidates

| # | Direction | D | R | F | S | Total |
|---|-----------|---|---|---|---|-------|
| 1 | **Pure Geometric (refine current)** — polish shapes, better glow, sharper outlines | 4 | 5 | 5 | 5 | 19 |
| 2 | **Full Kenney Pixel Art swap** — replace all shapes with Kenney sprites | 2 | 4 | 4 | 3 | 13 |
| 3 | **Neon Geometric** — current style + bloom, trails, chromatic aberration | 5 | 4 | 5 | 4 | 18 |
| 4 | **Geometry Wars style** — vector art, bright lines on black, particle-heavy | 5 | 4 | 4 | 4 | 17 |
| 5 | **Kenney + glow hybrid** — Kenney sprites with current glow/aura system | 3 | 4 | 4 | 3 | 14 |
| 6 | **Minimalist abstract** — even simpler shapes, pure color+motion communication | 4 | 5 | 5 | 5 | 19 |
| 7 | **Silhouette-only** — solid colored shapes, no internal detail | 3 | 4 | 5 | 4 | 16 |
| 8 | **Outlined wireframe** — no fill, only glowing outlines | 4 | 3 | 5 | 4 | 16 |
| 9 | **PixelLab custom sprites** — AI-generated pixel art via MCP | 3 | 4 | 4 | 4 | 15 |
| 10 | **Hybrid: geo player + sprite enemies** — shapes for player/bullets, Kenney for enemies | 3 | 4 | 4 | 3 | 14 |
| 11 | **Particle-entity style** — everything is particle clusters, no solid shapes | 4 | 2 | 4 | 3 | 13 |
| 12 | **Dual aesthetic** — geometric gameplay, pixel art menus/UI | 3 | 4 | 4 | 3 | 14 |
| 13 | **Monochrome geometric** — single hue per element type, high contrast | 3 | 5 | 5 | 4 | 17 |
| 14 | **Retro CRT** — current geo + scanlines + CRT shader + screen curvature | 4 | 4 | 5 | 3 | 16 |
| 15 | **Low-poly 2D** — triangulated shapes instead of circles | 3 | 4 | 4 | 4 | 15 |
| 16 | **Dot-cluster art** — entities as clusters of small dots | 3 | 3 | 4 | 3 | 13 |
| 17 | **Paper cutout** — flat shapes with torn edges and layered shadows | 3 | 4 | 3 | 3 | 13 |
| 18 | **Hand-drawn sketch** — rough lines, sketchy outlines | 3 | 3 | 2 | 2 | 10 |
| 19 | **Tron-line** — thin bright lines on dark bg, circuit-board aesthetic | 4 | 3 | 4 | 4 | 15 |
| 20 | **Evolving geometric** — shapes become more complex as player levels up | 4 | 4 | 4 | 3 | 15 |

---

## Top 6 (sorted by total score)

| Rank | Direction | D | R | F | S | Total |
|------|-----------|---|---|---|---|-------|
| 1 | **Pure Geometric (refined)** | 4 | 5 | 5 | 5 | 19 |
| 2 | **Minimalist Abstract** | 4 | 5 | 5 | 5 | 19 |
| 3 | **Neon Geometric** | 5 | 4 | 5 | 4 | 18 |
| 4 | **Geometry Wars** | 5 | 4 | 4 | 4 | 17 |
| 5 | **Monochrome Geometric** | 3 | 5 | 5 | 4 | 17 |
| 6 | **Retro CRT** | 4 | 4 | 5 | 3 | 16 |

**Eliminated**: All pixel art directions (Kenney, PixelLab, hybrid) scored 13-15. They sacrifice the game's distinctiveness for "looking like every other VS-like."

---

## 6 → 3 Analysis

### Cut: Monochrome Geometric (17pt)
Reducing to single-hue-per-element removes the semantic color system that's already locked. Going monochrome means losing fire=orange, cold=blue, etc. The current palette works. Monochrome is a downgrade disguised as minimalism.

### Cut: Retro CRT (16pt)
CRT shaders are a post-processing layer, not a direction. Can be added to ANY of the remaining options later. It's an enhancement, not a foundation.

### Cut: Geometry Wars (17pt)
While distinctive, the "vector line art" look requires significantly different rendering approach. Current shader system draws filled shapes — switching to thin-line-only is a larger migration than it appears, and readability drops at small sizes.

### The 3 Finalists

| Code | Direction | Key Idea |
|------|-----------|----------|
| **A** | **Pure Geometric (Refined)** | Keep current shapes. Add polish: better outlines, smoother animations, subtle idle animations (breathing/pulsing). Ship what works. |
| **B** | **Neon Geometric** | Current shapes + bloom shader + motion trails + chromatic aberration. Lean into the "arcade neon" aesthetic. More visually striking in screenshots. |
| **C** | **Minimalist Abstract** | Simplify further. Remove unnecessary detail. Let the color palette and motion do all communication. "Less is more" philosophy pushed to its logical end. |

---

## 3 → 1 Decision

### A: Pure Geometric (Refined)
**Pros**:
- Lowest risk (incremental improvement to what works)
- Fastest to implement (no shader rewrites)
- art_config.json already locked for this
- Readability is already maximal

**Cons**:
- Screenshots still look "programmer art" to casual browsers
- No visual wow factor for storefront listings
- "Just polish" doesn't create marketing moments

### B: Neon Geometric
**Pros**:
- Screenshots pop (bloom + trails = eye-catching)
- Distinctiveness jumps from 4→5 in market context
- Geometry Wars, SNKRX, and HoloCure prove neon-geo can sell
- Bloom + trails are Godot shader features, no external tools needed
- Creates a visual brand ("the neon one") that scales to future games

**Cons**:
- Bloom can hurt readability if overdone → needs careful tuning
- Chromatic aberration is divisive (some players hate it) → must be optional/toggleable
- Performance: bloom is a full-screen post-process, adds GPU cost on web

### C: Minimalist Abstract
**Pros**:
- Maximum readability
- Maximum scalability (every factory game can use this system)
- Fastest iteration speed (fewer visual elements to maintain)

**Cons**:
- Risk of looking "too simple" / "unfinished" on storefronts
- Hard to create compelling screenshots
- No marketing hook ("it's simple by design" is a tough sell)

---

## THE ONE: B — Neon Geometric

### Why

1. **Market differentiation**: In a sea of pixel-art VS-likes, a neon-geometric game stands out. The comparison is Geometry Wars (Xbox 360's #1 arcade hit) and SNKRX (500K+ sales with geometric shapes)
2. **Screenshot appeal**: Bloom and motion trails make screenshots and GIFs dramatically more attractive — critical for itch.io/Reddit/Twitter impressions
3. **Preserves readability**: The existing 4-tier visual hierarchy remains intact. Bloom is additive (brightens threats), not obscuring
4. **Fully autonomous**: Godot's `WorldEnvironment` node handles bloom (Glow effect). Motion trails use `Line2D` or shader. No external tools, no artist, no approval needed
5. **Factory brand**: "Neon geometric" can become a visual identity across all factory games. Consistency builds brand recognition
6. **Additive, not replacement**: This direction adds effects ON TOP of current shapes. If bloom causes problems, disable it — game still works

### Adoption/Rejection Criteria

**ADOPT if**:
- [ ] Bloom shader runs at 60fps in WebGL build (the primary distribution)
- [ ] Readability test: 3 autoplay runs with bloom ON show no survival time regression vs bloom OFF
- [ ] Screenshot comparison: bloom-on screenshots are rated higher than bloom-off (subjective, but CC can evaluate contrast and visual interest metrics)

**REJECT if**:
- WebGL performance drops below 45fps average with bloom enabled
- Any enemy type becomes harder to see (especially red enemies on dark red glow)
- Total WASM+assets size increases by >5MB

### Minimum Implementation Plan (v0.4.0)

```
Phase 1: WorldEnvironment + Glow (2 hours)
  - Add WorldEnvironment node to main scene
  - Enable Glow effect with conservative settings
  - Glow threshold = 0.8 (only bright elements bloom)
  - Glow bloom = 0.3 (subtle, not overwhelming)
  - Test in WebGL

Phase 2: Motion Trails (3 hours)
  - Player: short cyan trail (Line2D, 8-frame history)
  - Projectiles: element-colored trail (shorter, 4-frame)
  - Enemies: no trail (keeps threat contrast clear)
  - Use _physics_process for trail point recording

Phase 3: Polish (2 hours)
  - Enemy death: bright flash + particle burst
  - Level-up: screen-wide glow pulse
  - Boss entrance: chromatic aberration pulse (0.3s, optional in settings)
  - Update screenshots for itch.io/GitHub

Phase 4: Validate (1 hour)
  - WebGL performance test (3 runs, measure FPS)
  - Autoplay survival time comparison (bloom on vs off)
  - Screenshot before/after comparison
```

### What Kenney Packs Are For (Not Wasted)

The 7 downloaded Kenney packs still have value:
- **UI elements** (pixel-ui-pack): Menu buttons, health bar frames, item icons
- **Particle textures** (particle-pack): Better particle sprites for explosions
- **Reference**: Enemy design inspiration for new geometric enemy shapes

The packs augment the neon-geometric direction rather than replacing it.

---

*Generated by 20→6→3→1 Art Direction Analysis v2*
