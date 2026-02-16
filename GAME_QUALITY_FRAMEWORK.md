# Autonomous Game Quality Evaluation Framework

A practical, objective self-evaluation system for AI agents to assess game quality
without human playtesting. Designed to replace subjective "does this feel good?" with
measurable signals and pass/fail criteria.

---

## Part 1: Theoretical Foundations

### 1.1 Academic Heuristic Models (What We Draw From)

Three established frameworks inform this system. None are directly usable by an AI
agent as-is, but their categories map onto observable signals.

**GameFlow Model (Sweetser & Wyeth, 2005)** -- 8 elements of player enjoyment:

| Element | What It Measures | AI-Observable? |
|---------|-----------------|----------------|
| Concentration | Does the game demand attention without overwhelming? | Partial: screen density, simultaneous info streams |
| Challenge | Does difficulty increase appropriately? | Yes: progression curves, death/retry rates via bot |
| Player Skills | Can the player develop mastery? | Partial: skill ceiling analysis, mechanic depth |
| Control | Does the player feel in control? | Yes: input latency, response consistency |
| Clear Goals | Does the player know what to do? | Yes: presence of objective UI, tutorial coverage |
| Feedback | Does the game respond to player actions? | Yes: event->response mapping audit |
| Immersion | Is the player drawn into the world? | Partial: visual/audio cohesion metrics |
| Social Interaction | Can players interact? | N/A for single-player |

**PLAY Heuristics (Desurvire et al., 2009)** -- 8 categories:
- Game Play, Skill Development, Tutorial, Strategy & Challenge,
  Game/Story Immersion, Coolness, Usability/Game Mechanics, Controller/Keyboard
- Key insight: "Games need to be fun, not just usable." Standard usability
  heuristics miss engagement, pacing, and emotional arc.

**Pinelle Game Usability Heuristics (2008)** -- 10 principles:
1. Predictable game response to user actions
2. Customizable video, audio, difficulty, speed settings
3. Predictable/reasonable NPC behavior
4. Clear, unobstructed views
5. Ability to skip non-playable/repeated content
6. Intuitive and customizable input mappings
7. Controls with appropriate sensitivity and responsiveness
8. Visible game status information
9. Instructions, training, and help available
10. Visual representations that are easy to interpret, minimize micromanagement

### 1.2 What Can vs. Cannot Be Tested Programmatically

| Fully Automatable | Partially Automatable | Requires Human Judgment |
|-------------------|-----------------------|------------------------|
| Frame rate stability | Difficulty curve shape | "Is this fun?" |
| Input-to-response latency | Visual clarity/readability | Emotional resonance |
| Color contrast ratios | Animation smoothness feel | Narrative coherence |
| UI element sizes | Audio mix balance | Humor/tone effectiveness |
| Event coverage (all actions produce feedback) | Reward timing | Surprise/delight factor |
| Code-level bug detection | Screen information density | "Does this feel right?" |
| Asset presence/completeness | Color harmony | Cultural appropriateness |
| Save/load integrity | Tutorial effectiveness | Long-term engagement |

**Key principle**: Focus automation on what IS measurable. Use heuristic rules
for everything else. Accept that ~30% of game quality requires human response,
and design the framework to maximize the 70% an AI can assess.

---

## Part 2: Objective Metrics (Hard Numbers)

### 2.1 Performance Metrics

```
FRAME RATE
  - Target: 60 FPS stable (or 30 FPS for intentionally slow-paced games)
  - Measure: Run game for 5 minutes across all scenes
  - PASS:  95th percentile >= target, 1st percentile >= target * 0.8
  - WARN:  Any frame time spike > 33ms (30 FPS equivalent)
  - FAIL:  Average FPS < target * 0.9 or any freeze > 100ms

FRAME TIME CONSISTENCY
  - Measure: Standard deviation of frame times over 60-second windows
  - PASS:  StdDev < 2ms at 60 FPS target
  - WARN:  StdDev 2-5ms
  - FAIL:  StdDev > 5ms (perceptible stutter)

JANK DETECTION (per GameBench methodology)
  - Definition: Frame that takes >2x the target frame time
  - PASS:  < 1 jank per 10 seconds
  - WARN:  1-5 janks per 10 seconds
  - FAIL:  > 5 janks per 10 seconds
```

### 2.2 Input Responsiveness

```
INPUT-TO-VISUAL-RESPONSE LATENCY
  - Method: Timestamp input event, timestamp first visual change
  - Excellent:  < 30ms (input-to-photon)
  - Good:       30-50ms
  - Acceptable:  50-80ms
  - Poor:       80-120ms
  - Unacceptable: > 120ms

  For Godot: Measure frames between _input() call and visible change
  in _process(). Each frame at 60 FPS = ~16.7ms.

  PASS:  Response within same frame or next frame (0-16.7ms engine-side)
  WARN:  Response takes 2-3 frames (33-50ms)
  FAIL:  Response takes 4+ frames or is inconsistent

INPUT CONSISTENCY
  - The same input should produce the same response time every time
  - Measure: StdDev of response times for identical inputs over 100 trials
  - PASS:  StdDev < 1 frame
  - FAIL:  StdDev > 2 frames (player will perceive inconsistency)
```

### 2.3 Visual Clarity Metrics

```
CONTRAST RATIOS (adapted from WCAG 2.1)
  - Critical UI text (HP, score, objectives): >= 7:1 (AAA)
  - Standard UI text (menus, descriptions):   >= 4.5:1 (AA)
  - Large decorative text:                     >= 3:1
  - Interactive elements vs background:        >= 3:1
  - Method: Sample foreground/background colors, compute relative luminance ratio

  Formula: contrast = (L1 + 0.05) / (L2 + 0.05)
  where L = 0.2126*R + 0.7152*G + 0.0722*B (linearized sRGB)

UI ELEMENT SIZING
  - Minimum touch/click target: 44x44 pixels at reference resolution
  - Critical game elements (player, enemies): >= 16x16 pixels at 1080p
  - Text minimum: 14px equivalent at reference resolution
  - PASS:  All interactive elements meet minimums
  - FAIL:  Any critical element below minimum

SCREEN DENSITY / VISUAL NOISE
  - Method: Count distinct visual elements per screen quadrant
  - Gameplay screens: 5-15 distinct moving elements is comfortable
  - WARN:  > 20 simultaneous moving elements without clear focal hierarchy
  - FAIL:  > 30 simultaneous elements with no depth/layer separation
  - Also measure: % of screen covered by UI vs. gameplay area
    PASS: UI overlay < 25% of screen during gameplay
    WARN: UI overlay 25-40%
    FAIL: UI overlay > 40%
```

### 2.4 Color Metrics

```
PALETTE COHESION
  - Method: Extract dominant colors from each scene. Check that:
    a) All colors belong to an identifiable scheme (analogous, complementary,
       triadic, split-complementary)
    b) Maximum 5-7 dominant hues per scene (more = visual noise)
    c) Consistent saturation range (all muted, all vibrant, or intentional contrast)
  - Use HSLuv color model for perceptual uniformity

COLOR ACCESSIBILITY
  - Never rely solely on red/green distinction for game-critical information
  - Important status indicators must use shape + color (not color alone)
  - Test: Convert screenshot to grayscale; all critical info must remain readable
  - Test: Simulate deuteranopia/protanopia; verify no information loss

BACKGROUND-FOREGROUND SEPARATION
  - Gameplay elements must be clearly distinguishable from background
  - Method: Measure average luminance difference between:
    - Player character vs. typical background: >= 30% luminance difference
    - Enemy/hazard vs. background: >= 25% luminance difference
    - Collectibles vs. background: >= 20% luminance difference
```

---

## Part 3: Heuristic Checks (Rule-Based Assessment)

### 3.1 Feedback Completeness Audit

Every player action must produce observable feedback. Audit by mapping:

```
ACTION -> FEEDBACK MAPPING TABLE

For each player action in the game, check:
  [ ] Visual feedback exists (animation, particle, color change)
  [ ] Audio feedback exists (sound effect)
  [ ] Timing: feedback occurs within 1-2 frames of action
  [ ] Proportionality: important actions get bigger feedback

Scoring:
  5/5: Every action has visual + audio + proportional feedback
  4/5: 90%+ coverage, minor actions may lack audio
  3/5: 70-90% coverage, some actions feel "dead"
  2/5: 50-70% coverage, noticeable gaps in feedback
  1/5: < 50% coverage, game feels unresponsive

Common gaps to check:
  - Button hover states (visual change on mouseover?)
  - Button click feedback (press animation + sound?)
  - Damage dealt (hit flash + sound + number/particle?)
  - Damage received (screen flash/shake + sound + HP bar change?)
  - Item pickup (sound + visual effect + UI update?)
  - Level/area transition (fade/animation?)
  - Error states (invalid action attempt -> feedback?)
  - Empty states (nothing happening -> ambient life?)
```

### 3.2 Juice Inventory

Check for presence/absence of each juice category:

```
ESSENTIAL JUICE (missing any = amateurish feel)
  [ ] Easing functions on ALL UI animations (no linear interpolation)
  [ ] Screen shake on high-impact events (damage, explosions)
  [ ] Particle effects on destruction/collection events
  [ ] Hit-stop/freeze-frame on significant impacts (even 2-3 frames)
  [ ] Squash-and-stretch on character/entity movement
  [ ] Sound effects on all player actions
  [ ] Background music that matches scene mood

ADVANCED JUICE (presence = polished feel)
  [ ] Tweened number displays (HP/score count up/down, not jump)
  [ ] Damage numbers or floating text
  [ ] Trail effects on fast-moving objects
  [ ] Environmental reactions (grass bends, water ripples)
  [ ] Dynamic camera (subtle zoom on action, smooth follow)
  [ ] Layered audio (ambience + music + SFX at distinct levels)
  [ ] UI animations on state changes (slide in, bounce, fade)

EXPERT JUICE (presence = professional feel)
  [ ] Chromatic aberration / vignette on damage
  [ ] Time-scale manipulation (slow-mo on critical moments)
  [ ] Procedural animation overlays (idle breathing, anticipation frames)
  [ ] Contextual music changes (combat vs. exploration vs. danger)
  [ ] Persistent environmental marks (scorch marks, debris)
  [ ] Sound pitch/volume variation (same SFX never plays identically twice)
```

### 3.3 Tutorial and Onboarding

```
FIRST 30 SECONDS
  [ ] Player can interact within 5 seconds of game start (no long intros)
  [ ] Core mechanic is introduced through play, not text walls
  [ ] No more than 1 new concept per 30 seconds
  [ ] Player succeeds at something within first minute

INFORMATION ARCHITECTURE
  [ ] Controls are discoverable (shown on screen or taught by doing)
  [ ] Game objectives are stated explicitly somewhere accessible
  [ ] New mechanics are introduced one at a time
  [ ] Player can always find "what do I do next?" without external help

Scoring:
  5/5: Seamless onboarding through play, zero text tutorials
  4/5: Light tutorial popups, mostly learn-by-doing
  3/5: Tutorial screens but well-structured
  2/5: Text-heavy tutorial, some confusion likely
  1/5: No tutorial, player is abandoned
```

---

## Part 4: The "AI-Made" Detection (Anti-Patterns)

### 4.1 Things That Scream "Made by AI / Made by Amateur"

These are specific, detectable anti-patterns. Check for each:

```
VISUAL ANTI-PATTERNS
  [ ] Perfect geometric symmetry everywhere (real games break symmetry)
  [ ] Uniform spacing with zero variation (grid-perfect placement)
  [ ] All entities same size/scale (no visual hierarchy through size)
  [ ] Flat, uniform lighting (no shadows, no light sources, no mood)
  [ ] Placeholder-looking UI (plain rectangles, system fonts, no styling)
  [ ] Color palette is either too uniform or completely random
  [ ] Pixel art at inconsistent resolutions (some 16px, some 32px, some 64px)
  [ ] No visual weight hierarchy (everything screams for attention equally)

ANIMATION ANTI-PATTERNS
  [ ] Linear movement (no easing, things move at constant speed)
  [ ] Instant state changes (no transitions, things pop in/out)
  [ ] Identical animation timing on all elements (robotic feel)
  [ ] No anticipation frames (actions start without windup)
  [ ] No follow-through (actions end abruptly)
  [ ] Perfectly synchronized animations (real things are slightly offset)

AUDIO ANTI-PATTERNS
  [ ] No audio at all (instant amateur signal)
  [ ] Same sound plays identically every time (no pitch/volume variation)
  [ ] Music and SFX at same volume level (no mix hierarchy)
  [ ] Sound effects that don't match visual scale (tiny hit, huge boom)
  [ ] Silence during gameplay (no ambient audio layer)
  [ ] Audio clipping or distortion

GAMEPLAY ANTI-PATTERNS
  [ ] Difficulty is flat (no progression curve)
  [ ] All enemies behave identically
  [ ] Rewards are perfectly evenly spaced (no surprise, no anticipation)
  [ ] No downtime between intense moments (pacing is flat)
  [ ] Player has no meaningful choices (or all choices are equivalent)
  [ ] Death/failure has no consequence or feedback
```

### 4.2 Adding "Hand-Crafted Feel" Programmatically

Concrete techniques to counteract AI-made feel:

```
VARIATION INJECTION
  - Add +/- 5-15% random variation to timing values
  - Vary entity placement by small random offsets from grid
  - Use 2-3 slightly different versions of repeated elements
  - Randomize particle count, direction, lifetime within ranges
  - Pitch-shift sound effects by +/- 5-10% on each play

ORGANIC RHYTHM
  - Use sine/cosine for idle animations (breathing, bobbing)
  - Apply easing curves (ease-out for fast start, ease-in-out for natural)
  - Stagger spawn timing (not all at once, cascade with small delays)
  - Break visual symmetry: offset one element, vary one color slightly

INTENTIONAL IMPERFECTION
  - Align most things to grid, but offset a few by 1-2 pixels
  - Use hand-drawn or slightly irregular fonts for flavor text
  - Add subtle parallax or camera drift
  - Environmental "noise" layer (dust motes, ambient particles)
  - Slight asymmetry in UI layouts (not every panel identical)

PACING AND CONTRAST
  - Alternate high and low intensity moments
  - Insert brief pauses (300-500ms) before big events (anticipation)
  - Use silence strategically before audio crescendos
  - Vary reward frequency: clustered rewards feel better than uniform
```

---

## Part 5: The Scoring Rubric

### 5.1 Seven Dimensions, 1-5 Scale

Rate each dimension independently. A game is "ready for human eyes"
when it scores 3+ on all dimensions and 4+ on at least 3.

---

#### DIMENSION 1: VISUAL POLISH (Weight: High)

| Score | Observable Signals |
|-------|--------------------|
| 5 | Cohesive art style with consistent pixel resolution. Color palette is harmonious and intentional. Visual hierarchy is clear (player > enemies > environment > UI chrome). Lighting/shading creates mood. No placeholder art visible. Background-foreground separation is excellent. |
| 4 | Art is consistent and pleasant. Minor visual hierarchy issues. Color palette works but could be tighter. One or two elements feel slightly out of place. |
| 3 | Functional art that doesn't distract. Some inconsistency in style or resolution. Color palette is not actively ugly. Basic visual hierarchy exists. |
| 2 | Visible art inconsistencies. Some placeholder or mismatched art. Color palette is random or clashing. Hard to distinguish gameplay elements. |
| 1 | Placeholder art, inconsistent resolution, no color palette, no visual hierarchy. Godot default gray backgrounds visible. |

**Automated checks for this dimension:**
- Pixel resolution consistency across all sprites (programmatic)
- Color palette extraction and harmony analysis (programmatic)
- Contrast ratio measurement on all UI text (programmatic)
- Background clear color is not Godot default (programmatic)
- Screenshot comparison: no obvious placeholder rectangles (heuristic)

---

#### DIMENSION 2: AUDIO POLISH (Weight: High)

| Score | Observable Signals |
|-------|--------------------|
| 5 | Music fits mood and changes with context. All actions have distinct SFX. SFX have pitch/volume variation. Audio layers are properly mixed (music < SFX < critical alerts). Ambient audio fills silence. No clipping. |
| 4 | Good music and SFX coverage. Minor mix issues. Most actions have audio feedback. Some variation in repeated sounds. |
| 3 | Music exists and doesn't annoy. Major actions have SFX. Mix is acceptable. Some actions lack audio feedback. |
| 2 | Music exists but feels generic/mismatched. Many actions have no SFX. Audio mixing is poor. |
| 1 | No music or no SFX. Audio is jarring, clipping, or completely absent from gameplay. |

**Automated checks:**
- Count audio files in project vs. count of distinct game events (programmatic)
- Verify AudioStreamPlayer nodes exist for key events (programmatic)
- Check for pitch_scale randomization in SFX code (programmatic)
- Run game and detect silence periods > 3 seconds during gameplay (heuristic)
- Audio bus configuration exists (music/sfx/ambient separation) (programmatic)

---

#### DIMENSION 3: GAMEPLAY CLARITY (Weight: Critical)

| Score | Observable Signals |
|-------|--------------------|
| 5 | Player always knows: what they can do, what they should do, what just happened, and what changed. Zero moments of "what?" UI communicates all game state. Error states are handled gracefully. |
| 4 | Mostly clear. Rare moments of confusion. All critical information is visible. Minor actions might lack clarity. |
| 3 | Core loop is understandable. Some secondary mechanics are unclear. Player might need to experiment to understand some elements. |
| 2 | Frequent confusion about game state or objectives. Some UI elements are ambiguous. Player might not know they failed or succeeded. |
| 1 | Player cannot determine what to do, what happened, or how to proceed without external information. |

**Automated checks:**
- Tutorial/help system exists and is accessible (programmatic)
- All game states have visible indicators (HP bar, score, objective) (heuristic)
- Win/lose conditions produce distinct visual+audio feedback (heuristic)
- Pinelle H8: Status information is always visible (programmatic scan of UI)
- Pinelle H1: Actions produce predictable results (bot testing)

---

#### DIMENSION 4: REWARD TIMING & FEEDBACK LOOP (Weight: High)

| Score | Observable Signals |
|-------|--------------------|
| 5 | Actions feel impactful. Rewards trigger cascading feedback (visual + audio + number + screen effect). Variable reward timing creates anticipation. Short-term and long-term reward loops both exist. "One more turn" feeling. |
| 4 | Good feedback on most rewards. Some reward events feel undersold. Core loop has satisfying pacing. |
| 3 | Rewards exist and are noticeable. Feedback is functional but not exciting. Pacing is acceptable but flat. |
| 2 | Rewards are present but feedback is minimal (just a number increment). Pacing is monotonous. |
| 1 | No discernible reward feedback. Actions feel meaningless. No sense of progress. |

**Automated checks:**
- Map reward events to feedback channels (visual/audio/haptic) (heuristic)
- Verify reward events trigger 2+ feedback types simultaneously (programmatic)
- Check for score/progress tweening (not instant jumps) (programmatic)
- Analyze reward spacing: is there variance, or perfectly uniform? (bot telemetry)
- Hit-stop / freeze-frame code exists for impact events (programmatic)

---

#### DIMENSION 5: DIFFICULTY CURVE (Weight: Medium)

| Score | Observable Signals |
|-------|--------------------|
| 5 | Smooth difficulty ramp. Early levels teach mechanics through play. Challenge increases with new mechanics, not just bigger numbers. Failure teaches rather than punishes. Recovery is always possible. |
| 4 | Good progression. Minor difficulty spikes or flat spots. New mechanics are introduced at reasonable pace. |
| 3 | Difficulty exists and generally increases. Some levels feel too easy or too hard. Progression is functional. |
| 2 | Difficulty is flat or has harsh spikes. Little connection between skill and success. New mechanics are poorly introduced. |
| 1 | No difficulty progression, or starts impossibly hard, or trivially easy throughout. |

**Automated checks (via bot playtesting):**
- Bot success rate by level/wave: should decrease gradually (telemetry)
- Time-to-complete by level: should increase gradually (telemetry)
- Death/retry rate: should be low early, increase mid-game (telemetry)
- New mechanic introduction rate: max 1 per level/wave (programmatic)
- DDA research metric: completion rate per level should be 70-85% (telemetry)

---

#### DIMENSION 6: UI/UX (Weight: Critical)

| Score | Observable Signals |
|-------|--------------------|
| 5 | UI is intuitive, responsive, and beautiful. All interactive elements have hover/press states. Navigation is never more than 2 clicks from any destination. Text is readable at all sizes. Settings menu exists with audio/video options. |
| 4 | UI is clean and functional. Most elements have feedback states. Navigation is logical. Minor visual rough edges. |
| 3 | UI works. Some elements lack hover/press states. Navigation requires some discovery. Text is readable. |
| 2 | UI is functional but ugly or confusing. Missing feedback states. Navigation is unintuitive. Some text is hard to read. |
| 1 | UI is broken, missing, or actively confusing. No hover/press states. Navigation is a maze. Text is unreadable. |

**Automated checks:**
- All buttons have hover and pressed visual states (programmatic scan)
- Text contrast meets WCAG AA (4.5:1) minimum (programmatic)
- Click targets meet 44x44px minimum (programmatic)
- Settings menu exists with volume controls (programmatic)
- Pinelle H2: Video/audio/difficulty are customizable (programmatic)
- Pinelle H5: Non-playable content can be skipped (programmatic)
- Navigation depth from any screen to any other screen <= 3 (graph analysis)

---

#### DIMENSION 7: JUICE FACTOR (Weight: High)

| Score | Observable Signals |
|-------|--------------------|
| 5 | Every interaction sparkles. Screen shake, particles, tweens, sounds all work in concert. Effects are proportional to action importance. Game has personality through its feedback. "Maximum output for minimum input" principle achieved. |
| 4 | Most interactions feel juicy. A few minor actions lack flair. Overall the game feels alive and responsive. |
| 3 | Basic juice present: some particles, some shake, some tweening. Functional but not exciting. Game doesn't feel dead, but doesn't feel alive either. |
| 2 | Minimal juice. Most state changes are instant. Few particles or effects. Linear animations. Game feels flat. |
| 1 | Zero juice. No screen shake, no particles, no tweening, no easing. State changes are instant. Game feels like a spreadsheet. |

**Automated checks:**
- Count Tween nodes / tween calls in codebase (programmatic)
- Count CPUParticles2D / GPUParticles2D nodes (programmatic)
- Search for screen_shake / camera_shake function calls (programmatic)
- Verify easing constants used (EASE_IN, EASE_OUT, not LINEAR) (programmatic)
- Count AnimationPlayer nodes vs. total interactive entities (programmatic)
- Ratio of visual effect scripts to gameplay scripts (programmatic)

---

### 5.2 Score Interpretation

```
TOTAL SCORE (out of 35):

  30-35  SHIP IT       - Ready for public. Will impress.
  25-29  NEARLY THERE  - One round of polish away. Specific issues identified.
  20-24  SOLID ALPHA   - Core is good, needs systematic polish pass.
  15-19  EARLY ALPHA   - Functional but not ready for external eyes.
  10-14  PROTOTYPE     - Prove the concept works before polishing.
   7-9   SKELETON      - Game barely exists. Build more before evaluating.

MINIMUM VIABLE QUALITY for showing to humans:
  - No dimension below 3
  - At least 3 dimensions at 4+
  - Both Critical dimensions (Gameplay Clarity, UI/UX) at 4+
  - Total score >= 25
```

---

## Part 6: Automated Testing Implementation

### 6.1 Screenshot-Based Visual Regression

```
APPROACH: Capture baseline screenshots, compare after changes.

IMPLEMENTATION:
  1. Define key game states (title, gameplay, pause, game over, each menu)
  2. Capture reference screenshots for each state
  3. After code changes, recapture and compare
  4. Flag if pixel difference > 5% (expected variation from particles/animation)
  5. Flag if pixel difference > 20% (likely unintended change)

IN GODOT:
  - Use get_viewport().get_texture().get_image() to capture
  - Save as PNG with timestamp
  - Compare using image difference (pixel-by-pixel or perceptual hash)

WHAT TO CHECK:
  - UI elements haven't shifted or disappeared
  - Color palette hasn't changed unintentionally
  - No rendering artifacts (black rectangles, missing textures)
  - Text is still readable (not overlapping, not clipped)
```

### 6.2 Bot-Based Playtesting

```
APPROACH: Automated agent plays the game, collects telemetry.

SIMPLE BOT STRATEGIES:
  1. Random input bot: Presses random valid inputs. Detects crashes,
     soft-locks, and unreachable states.
  2. Optimal bot: Follows the "correct" path. Measures minimum completion
     time and verifies all content is reachable.
  3. Adversarial bot: Tries to break things. Rapid input switching,
     holding multiple buttons, edge-case combinations.

TELEMETRY TO COLLECT:
  - Frames alive before death (per attempt)
  - Total completion time (per level/wave)
  - Actions per minute (engagement proxy)
  - States visited (coverage metric)
  - Error/exception count
  - Frame rate during gameplay (performance under load)

SUCCESS CRITERIA:
  - Random bot: 0 crashes in 1000 random inputs
  - Random bot: 0 soft-locks (stuck states with no valid action)
  - Optimal bot: All levels completable
  - Optimal bot: Completion time is within 2x expected range
  - Adversarial bot: 0 crashes, no state corruption
```

### 6.3 Code-Level Quality Scan

```
STATIC ANALYSIS CHECKS:
  [ ] No TODO/FIXME/HACK comments in shipped code
  [ ] No print()/console debug output in shipped code
  [ ] All exported variables have sensible defaults
  [ ] No magic numbers without comments
  [ ] Error handling exists for file I/O, save/load, network
  [ ] No empty catch/except blocks that swallow errors

ASSET COMPLETENESS:
  [ ] All referenced textures exist (no broken paths)
  [ ] All referenced audio files exist
  [ ] All referenced scenes exist
  [ ] No placeholder filenames ("test.png", "temp.ogg", "untitled.tscn")
  [ ] Icon/branding is not Godot default

GODOT-SPECIFIC:
  [ ] project.godot has proper name and description
  [ ] Main scene is set and loads without error
  [ ] No autoload scripts are commented out (or remove them)
  [ ] Window size is set intentionally (not default 1152x648)
  [ ] Renderer is set intentionally
  [ ] Input map covers all used actions
```

---

## Part 7: Process -- How an AI Agent Uses This Framework

### 7.1 Pre-Evaluation Checklist

Before scoring, the agent must:
1. Build and run the game successfully
2. Capture screenshots of every distinct screen/state
3. Run a bot playthrough (or manual walkthrough via script)
4. Collect performance metrics from a 5-minute run
5. Complete the code-level scan

### 7.2 Evaluation Workflow

```
STEP 1: HARD METRICS (Part 2)
  Run all automated measurements. Record exact numbers.
  Any FAIL = must fix before proceeding to scoring.

STEP 2: HEURISTIC CHECKS (Part 3)
  Walk through each checklist. Mark items present/absent.
  Calculate coverage percentages.

STEP 3: ANTI-PATTERN SCAN (Part 4)
  Check each anti-pattern. Count violations.
  For each violation, note the specific fix needed.

STEP 4: DIMENSION SCORING (Part 5)
  Score each dimension 1-5 based on accumulated evidence.
  Write 1-sentence justification for each score.
  Calculate total.

STEP 5: ACTION PLAN
  If total < 25 or any dimension < 3:
    List top 3 highest-impact improvements.
    Prioritize by: (points gained) * (ease of implementation).
    Execute improvements.
    Re-evaluate.
```

### 7.3 Decision Framework for Design Choices

When the AI agent faces a design decision and cannot ask a human:

```
PRIORITY ORDER:
  1. Does it improve a dimension currently scored < 3? -> DO IT
  2. Does it fix a detected anti-pattern? -> DO IT
  3. Does it add Essential Juice that's missing? -> DO IT
  4. Does it improve a FAIL metric to PASS? -> DO IT
  5. Does it improve a dimension from 3 to 4? -> DO IT if fast
  6. Does it add Advanced/Expert Juice? -> DO IT only if basics are solid
  7. Does it change a subjective preference? -> DON'T (leave for human)
  8. Does it require choosing between two valid approaches? -> Pick the
     one that scores better on this framework, document the alternative
```

---

## Part 8: Quick Reference Card

### The 60-Second Evaluation

For rapid assessment, check these 10 things:

1. **Does the game run without errors?** (pass/fail)
2. **Is the frame rate stable?** (measure)
3. **Can you read all text?** (contrast check)
4. **Does every click/press produce feedback?** (audit)
5. **Is there music AND sound effects?** (presence check)
6. **Do animations use easing, not linear movement?** (code check)
7. **Are there particles/effects on impacts?** (presence check)
8. **Does the player know what to do?** (tutorial/objective check)
9. **Does difficulty change over time?** (progression check)
10. **Does anything look like a placeholder?** (visual scan)

Answering "no" to any of these = specific, actionable improvement target.

---

## Sources and References

### Academic Frameworks
- Sweetser & Wyeth (2005). "GameFlow: A Model for Evaluating Player Enjoyment in Games."
  Computers in Entertainment, 3(3). [ACM DL](https://dl.acm.org/doi/10.1145/1077246.1077253)
- Desurvire & Wiberg (2009). "Game Usability Heuristics (PLAY) for Evaluating and Designing
  Better Games." [Springer](https://link.springer.com/chapter/10.1007/978-3-642-02774-1_60)
- Pinelle, Wong & Stach (2008). "Heuristic Evaluation for Games: Usability Principles for
  Video Game Design." CHI 2008. [Semantic Scholar](https://www.semanticscholar.org/paper/60b1063b7bec0a5a90213fcb4b17e0e855797a1c)
- Hochleitner et al. "A Heuristic Framework for Evaluating User Experience in Games."
  [Springer](https://link.springer.com/chapter/10.1007/978-3-319-15985-0_9)

### Game Feel and Juice
- "The Metrics of Game Feel." [Kirs Turino](https://kirsturino.github.io/home/blog/gamefeel2.html)
- "Squeezing More Juice Out of Your Game Design." [GameAnalytics](https://www.gameanalytics.com/blog/squeezing-more-juice-out-of-your-game-design)
- "Juice in Game Design." [Brad Woods](https://garden.bradwoods.io/notes/design/juice)
- "Juice in Game Design: Making Your Games Feel Amazing." [Blood Moon Interactive](https://www.bloodmooninteractive.com/articles/juice.html)
- "Making Games Juicy." [Joys of Small Game Development](https://abagames.github.io/joys-of-small-game-development-en/make_game_juicy.html)
- "Measuring Responsiveness in Video Games." [Game Developer](https://www.gamedeveloper.com/design/measuring-responsiveness-in-video-games)
- "Advanced Game Animation Metrics: Janks and Frametimes." [GameBench](https://blog.gamebench.net/advanced-game-animation-metrics-janks-and-frametimes)

### Automated Testing
- "How AI Is Revolutionizing Game QA in 2025." [ThinkGamerz](https://www.thinkgamerz.com/ai-in-game-qa/)
- "Leveraging AI for Automated Testing and Quality Assurance in Game Development." [Getgud.io](https://www.getgud.io/blog/leveraging-ai-for-automated-testing-and-quality-assurance-in-game-development/)
- "Running an Automated Test Pipeline for the League Client Update." [Riot Games Technology](https://technology.riotgames.com/news/running-automated-test-pipeline-league-client-update)
- "How Modl.ai and Riot Games Are Redefining AI Bots." [Modl.ai](https://modl.ai/riot-games-and-modl-shooter-bots)
- "Leveraging LLM Agents for Automated Video Game Testing." [arXiv](https://arxiv.org/html/2509.22170v1)
- GamingAgent (ICLR 2026). [GitHub](https://github.com/lmgame-org/GamingAgent)

### Telemetry and Analytics
- "What Is Game Telemetry?" [GameAnalytics](https://www.gameanalytics.com/blog/what-is-game-telemetry)
- "Key Metrics in Game Analytics." [ELVTR](https://elvtr.com/blog/key-metrics-in-game-analytics-measuring-and-optimizing-game-performance)
- "A Comprehensive Model of Automated Evaluation of Difficulty in Platformer Games." [ACM](https://dl.acm.org/doi/10.1145/3705013)

### Difficulty and Balance
- "Assessing Video Game Balance using Autonomous Agents." [arXiv](https://arxiv.org/pdf/2304.08699)
- "Difficulty Curves: How to Get the Right Balance." [Game Developer](https://www.gamedeveloper.com/design/difficulty-curves-how-to-get-the-right-balance-)

### Visual Accessibility
- WCAG 2.1 Contrast Requirements. [WebAIM Contrast Checker](https://webaim.org/resources/contrastchecker/)
- HSLuv Perceptual Color Model. [Accessible Palette](https://accessiblepalette.com/)

### Procedural Generation and Organic Feel
- "Level Design in Procedural Generation." [Game Developer](https://www.gamedeveloper.com/design/level-design-in-procedural-generation)
- "Devs Weigh In on the Best Ways to Use Procedural Generation." [Game Developer](https://www.gamedeveloper.com/design/devs-weigh-in-on-the-best-ways-to-use-but-not-abuse-procedural-generation)
