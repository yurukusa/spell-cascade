# VS-Like (Vampire Survivors-Like) Game Design Research

Comprehensive research document covering reward loops, power curves, level-up pacing, visual feedback ("juice"), and difficulty curves in the survivors-like / bullet heaven genre.

---

## 1. Reward Loop Design

### The Core Loop

The fundamental VS-like loop is: **Kill enemies -> Get XP -> Level up -> Choose upgrade -> Kill faster -> Repeat**

This loop succeeds because it compresses the RPG power fantasy into a single 15-30 minute session. Every run is a complete hero's journey from weakness to godhood.

### Why It Works: Psychological Foundations

**Variable Ratio Reinforcement (Casino Psychology)**
Luca Galante, Vampire Survivors' creator, worked in the online gambling industry before making the game. He explicitly brought casino design principles into VS:

- **Chest openings use slot-machine animations**: Bands of color, scrolling symbols, coin fountains, win jingles. Galante stated: "In the slot machine industry, the player is actually spending money every time they press it, and because of that, there's a huge attention to detail on the sounds, the animations, and the sequences." (Source: [The Conversation](https://theconversation.com/vampire-survivors-how-developers-used-gambling-psychology-to-create-a-bafta-winning-game-203613))
- **Hardcoded early chest rewards**: The first 6 chests in Vampire Survivors contain 1-1-3-1-5 items respectively, setting inflated expectations before odds drop. This is the same "early win" technique casinos use on new players. (Source: [JB Oger - Secret Sauce of VS](https://jboger.substack.com/p/the-secret-sauce-of-vampire-survivors))
- **Near-miss effect**: Every run that doesn't reach 30 minutes triggers the feeling "I was so close." This activates the same reward centers as actual wins. (Source: [The Conversation](https://theconversation.com/vampire-survivors-how-developers-used-gambling-psychology-to-create-a-bafta-winning-game-203613))

**Self-Determination Theory (SDT)**
VS-likes satisfy all three psychological needs from the Player Experience of Needs Satisfaction Model:
1. **Competence**: Automatic attacks + frequent upgrades create constant mastery signals
2. **Autonomy**: 49+ characters and build variety enable diverse playstyles
3. **Relatedness**: Character homages, community meta discussions

**Flow State Optimization**
The game maintains "optimal challenges" balanced within player capabilities. The key insight: by automating attacks, VS removes the skill floor for combat. The only skill is movement and build selection, keeping cognitive load manageable while still offering meaningful choices.

### Reward Timing: The Critical Numbers

**Vampire Survivors**: Upgrades arrive approximately every **23 seconds** rather than every 2.5 minutes. The designer deliberately separates upgrades into many small tiers rather than fewer major jumps. This prevents "reward valleys" that break engagement. (Source: [JB Oger](https://jboger.substack.com/p/the-secret-sauce-of-vampire-survivors))

**Brotato**: Wave 1 lasts only **20 seconds**, increasing by 5 seconds per wave until capping at **60 seconds** at wave 9. Between every wave, there's a shop phase for upgrades. A full run takes 15-20 minutes. The ultra-short early waves mean you're making upgrade decisions within seconds of starting. (Source: [Brotato Wiki](https://brotato.wiki.spellsandguns.com/Waves), [Adrian Hon](https://adrianhon.substack.com/p/brotato))

**Halls of Torment**: Ability level-ups are gated: 1 ability level every 8 character levels. This creates a slower, more deliberate pacing closer to Diablo than VS. The tradeoff: each upgrade feels weightier, but the dopamine frequency is lower. (Source: [Halls of Torment Wiki](https://hot.fandom.com/wiki/Trait))

### The Vacuum/Magnet Moment

One of VS's most brilliant design elements: the vacuum pickup that sucks all XP gems on screen toward the player. This creates a single moment of overwhelming reward -- thousands of gems streaming in, triggering rapid-fire level-ups, accompanied by cascading audio feedback. It validates all the chaos the player survived and creates a "reward avalanche" that's psychologically irresistible. (Source: [KokuTech](https://www.kokutech.com/blog/gamedev/design-patterns/power-fantasy/vampire-survivors))

### Comparative Reward Structures

| Game | Reward Frequency | Reward Type | Between-Run Rewards |
|------|-----------------|-------------|-------------------|
| **Vampire Survivors** | ~23 seconds | Pause menu choice (3-4 options) | Gold for permanent stat PowerUps |
| **Brotato** | Every 20-60 second wave | Shop between waves | Character/weapon unlocks |
| **Halls of Torment** | Every 8 levels for abilities | Trait selection on level-up | Blessings (permanent buffs via gold) |
| **Soulstone Survivors** | Per level-up (frequent) | Power selection + skill tree | Soulstones for global/character skill trees |
| **20 Minutes Till Dawn** | Per level-up | Upgrade selection | Character/weapon unlocks |

---

## 2. Power Curve Design

### The Arc: Weakness to Godhood

Every VS-like run follows the same emotional power arc:

```
Power Level
    ^
    |                              /-------- GODHOOD (endgame)
    |                            /
    |                          /
    |                       /
    |                    /     <- Exponential growth phase
    |                 /
    |              /
    |           /
    |        /
    |     /
    |   / <- Steady linear growth
    |  /
    | /
    |/ <- Vulnerable start
    +-----------------------------------------> Time (minutes)
    0    5    10    15    20    25    30
```

**Phase 1 (0-2 min): Vulnerability**
- Single weak weapon, low stats
- Player feels fragile, every enemy is a threat
- Purpose: Establishes the baseline so growth feels meaningful
- First level-up within 30-60 seconds

**Phase 2 (2-10 min): Building Momentum**
- Acquiring 2-4 weapons, basic passives
- Power growth feels linear -- steady improvement
- Player starts to feel "I can handle this"
- Critical period: if growth is too slow here, players quit

**Phase 3 (10-20 min): Exponential Explosion**
- Weapon evolutions unlock (VS requires level 8 weapon + matching passive)
- Synergies compound: multiple weapons firing simultaneously
- Screen fills with projectiles
- Player transitions from "surviving" to "dominating"

**Phase 4 (20-30 min): Power Fantasy Peak**
- Near-invincibility with maxed build
- Hundreds/thousands of enemies dying per second
- Player feels like a god
- Purpose: This is the payoff for the entire session

### Meta-Progression: The Between-Run Multiplier

Vampire Survivors uses permanent PowerUps purchasable with gold between runs. These create approximately **2.5x damage and 2x health** compared to baseline -- but players don't perceive this as grinding because individual upgrades feel minor. (Source: [JB Oger](https://jboger.substack.com/p/the-secret-sauce-of-vampire-survivors))

Key design principle: **Meta-progression should make early-run vulnerability shorter, not eliminate it.** The opening weakness is essential to the power arc.

### Player Power vs. Enemy Scaling

**Critical insight from VS**: Enemy difficulty scales with **time elapsed**, NOT player level. This means:
- Leveling faster makes you genuinely stronger (no rubber-banding)
- Player investment in XP collection is always rewarded
- There's no "catch-up" mechanic that punishes good play
(Source: [Steam Community](https://steamcommunity.com/app/1794680/discussions/0/3489752656787156939/))

**Halls of Torment** takes a different approach: enemies have stat modifiers per-stage and difficulty mode. Boss HP scales with player level and Curse stat, creating intentional tension between power and challenge.

### Build Slot Design

The standard VS-like build structure: **6 weapon slots + 6 passive item slots**. Once all slots are filled and maxed, level-ups yield gold/consumables instead. This creates a natural build completion arc:
- Early: Every level-up adds a new capability
- Mid: Upgrading existing capabilities
- Late: Build is "complete," mastery phase begins
(Source: [VS Wiki](https://vampire.survivors.wiki/w/Passive_items))

### Weapon Evolution System

The evolution mechanic (base weapon + specific passive = evolved weapon) serves multiple design purposes:
1. **Discovery reward**: Hidden recipes encourage experimentation
2. **Strategic depth**: Players must plan passive items around desired evolutions
3. **Power spike moments**: Evolutions are massive upgrades that feel incredible
4. **Mid-run milestone**: Evolutions typically occur around minutes 10-15, perfectly timed with the exponential growth phase

---

## 3. Level-Up Frequency and Upgrade Menu Design

### XP Curve: Vampire Survivors Specifics

The XP requirements follow a tiered scaling system:

| Level Range | XP Increase Per Level | Special Rules |
|-------------|----------------------|---------------|
| 1-2 | 5 XP (flat) | First level-up in ~30 seconds |
| 2-20 | +10 XP per level | Level 20: +600 extra XP, but +100% Growth |
| 21-40 | +13 XP per level | Level 40: +2400 extra XP, but +100% Growth |
| 41+ | +16 XP per level | Continues indefinitely |

The Growth bonus at level 20 and 40 thresholds is clever: it creates a "plateau" where progress temporarily slows (building tension), then accelerates dramatically (releasing tension with doubled XP gain).
(Source: [VS Wiki - Level Up](https://vampire-survivors.fandom.com/wiki/Level_up))

### Ideal Level-Up Frequency by Game Phase

Based on analysis across successful VS-likes:

| Phase | Time Range | Ideal Level-Up Interval | Purpose |
|-------|-----------|------------------------|---------|
| Opening | 0-2 min | Every 10-15 seconds | Hook the player, immediate reward |
| Early | 2-5 min | Every 15-25 seconds | Maintain momentum, build variety |
| Mid | 5-15 min | Every 25-40 seconds | Strategic choices, evolution prep |
| Late | 15-25 min | Every 40-60 seconds | Build refinement, gold accumulation |
| Endgame | 25-30 min | Every 60-90 seconds | Diminishing returns, shift focus to survival |

### Preventing "Upgrade Menu Fatigue"

The tension: frequent upgrades create dopamine hits, but too many pause-menu interruptions break flow.

**Solutions used by successful VS-likes:**

1. **Vampire Survivors**: 3-4 options per level-up. Reroll and skip buttons for experienced players. Banish system to remove unwanted options permanently. Quick decision = quick return to action.

2. **Brotato**: Separates combat (wave) from upgrades (shop). The shop is a distinct phase between waves where you can browse without time pressure. This avoids the VS problem of constant menu interruptions during combat.

3. **Halls of Torment**: Fewer, more meaningful level-ups. Ability choices every 8 levels instead of every level. Each choice feels weighty.

4. **Soulstone Survivors**: Powers have rarity tiers (Common through Legendary). This makes some choices trivially fast ("obviously pick Legendary") while others require thought.

**Key principle**: As the game progresses and the player has a clearer build identity, level-up choices should become faster (fewer viable options) or less frequent (longer between levels). The worst case is frequent menus with too many equally-viable choices.

### The "Skip" Button Philosophy

VS added a Skip button for level-ups. This seems counterintuitive -- why let players skip rewards? Because:
- Experienced players know which items to avoid
- Skipping creates a meaningful strategic choice (gold vs. bad option)
- It respects player time and autonomy
- It prevents the frustration of being forced to take something harmful to your build

---

## 4. Visual Feedback / "Juice"

### Core Juice Techniques for VS-Likes

**Screen Shake**
- Vlambeer's "Art of Screenshake" GDC talk is the foundational reference
- Best practice: map shake intensity to event significance on a scale
- Adding **0.1 seconds of still frame** between shake segments increases perceived impact strength by ~30%
- Warning: excessive shake in VS-likes causes motion sickness (VS added a disable option)
(Source: [Oreate AI Research](https://www.oreateai.com/blog/research-on-the-mechanism-of-screen-shake-and-hit-stop-effects-on-game-impact/decf24388684845c565d0cc48f09fa24))

**Hit Stop / Freeze Frame**
- Optimal duration: **50-150 milliseconds** (0.05-0.15 seconds)
- Duration exceeding 0.15 seconds reduces satisfaction in speed-focused genres
- Light attacks: ~9 frames (~150ms at 60fps). Medium: ~11 frames. Heavy: ~13 frames
- **Selective freezing** is superior: pause attacker and target, but keep particles and other enemies moving
- Purpose: "Gives the eyes a few frames to register the collision happened"
(Source: [Oreate AI](https://www.oreateai.com/blog/research-on-the-mechanism-of-screen-shake-and-hit-stop-effects-on-game-impact/decf24388684845c565d0cc48f09fa24), [Source Gaming - Sakurai on Hitstop](https://sourcegaming.info/2015/11/11/thoughts-on-hitstop-sakurais-famitsu-column-vol-490-1/))

**Important VS-like caveat**: Traditional hitstop becomes impractical when killing hundreds of enemies per second. VS-likes must use lighter-weight feedback:
- Brief enemy flash (white or red) on hit -- 1-2 frames
- Death particles (blood splatter, dissolve effect, poof)
- Damage numbers (floating text, scaling with damage)
- XP gem spawn with slight physics scatter

**Damage Numbers**
VS shows floating damage numbers above enemies. While some players find them cluttered, they serve as constant "progress!" feedback. The appeal: "the satisfying feeling of doing the thing." Turning off damage numbers and flash effects provides an instant FPS improvement, revealing their performance cost.
(Source: [Steam Community](https://steamcommunity.com/app/1794680/discussions/0/3470612993483101082/))

**Particle Systems**
Essential particle effects for VS-likes:
- Enemy death: burst of particles in enemy's color palette
- XP gem collection: trail effect as gems fly toward player
- Level-up: radial burst around player, screen flash
- Weapon fire: muzzle flash, projectile trail, impact splash
- Evolution unlock: dramatic full-screen effect
- Chest opening: coin fountain, light beams

**The Vacuum Effect**
When the vacuum item activates and all XP gems fly toward the player simultaneously, it creates arguably the most satisfying visual moment in the genre. The visual: hundreds of colored gems streaming from all directions, accompanied by a cascading collection sound. This is VS's signature "juice" moment.

### Sound Design Principles

**Layered Audio Feedback Loop:**
The audio in VS "is simple but effective and quickly layers up." Individual sounds are quiet and brief, but they compound:
- Gem collection: soft chime, slightly randomized pitch
- Enemy death: brief pop/squelch
- Weapon fire: rhythmic, satisfying thud/whoosh
- Level-up: fanfare stinger that cuts through the mix
- Chest opening: slot-machine jingle with escalating excitement
- Evolution: dramatic reveal sound

**Key principle**: Individual sound effects must be short and unobtrusive because dozens play simultaneously. The **cumulative layering** creates the satisfying "symphony of destruction."

**Casino-Inspired Audio Design:**
Galante noted: "One of the slot games had a really good jingle when a treasure chest opened." The chest-opening sequence in VS directly mimics slot machine audio patterns -- building anticipation through escalating sounds before the reward reveal.

### VS-Like Specific Visual Design

**What VS-likes do differently from traditional action games:**

1. **Readability over beauty**: Enemy sprites are simple and distinct. The player must instantly parse hundreds of entities
2. **Player always visible**: Character stays at screen center with high contrast against enemy swarms
3. **Progressive visual chaos**: The screen literally fills up over 30 minutes. Early: clean and readable. Late: beautiful chaos that rewards the player visually for their power
4. **Damage as decoration**: Late-game weapon effects become the primary visual element, replacing environmental art. The player's attacks ARE the spectacle

---

## 5. Difficulty Curve and Tension Design

### The VS-Like Emotional Arc

```
Tension
    ^
    |    *                      *
    |   * *                    * *
    |  *   *        *   *     *   *
    | *     *      * * * *   *     *
    |*       *    *       * *       *  <- DEATH/REAPER
    |         *  *         *         *
    |          **
    +-----------------------------------------> Time (minutes)
    0    5    10    15    20    25    30

    LOW          MEDIUM       HIGH    PEAK
    (Learning)   (Growing)    (Power)  (Finale)
```

**Minute 0-5: Careful Navigation**
- Few enemies, low danger
- Tension comes from vulnerability, not quantity
- Player learns movement patterns
- Each enemy matters individually

**Minute 5-10: Rising Challenge**
- Enemy density increases noticeably
- Tougher enemy types appear (bats at minute 9 in Mad Forest)
- Player's growing arsenal just barely keeps pace
- First "close calls" create engagement spikes

**Minute 10-15: The Crisis Point**
- Dramatic enemy density increase (minute 11+ in Mad Forest)
- This is where unprepared builds die
- Weapon evolutions become available, creating massive power spikes
- **The emotional pivot**: tension peaks, then power fantasy kicks in

**Minute 15-25: Power Fantasy**
- Evolved weapons shred everything
- Enemy quantity remains high but poses diminishing threat
- Player feels increasingly godlike
- Tension is low but satisfaction is maximum
- From minute 16-24 in Mad Forest: mainly strong individual enemies appear with decreased spawn frequency (quality over quantity)

**Minute 25-30: Final Stand / Crescendo**
- Enemy spawns intensify again (minute 25+ in Mad Forest)
- Player's build is finalized -- no more upgrades coming
- Tension builds toward the climax
- Giant bosses appear (Giant Blue Venus at 25:00 in Mad Forest)

**Minute 30: The Reaper**
- All enemies cleared, the Reaper spawns (invincible death entity)
- This is the "hard stop" -- the session MUST end
- Additional Reapers spawn every minute after 30
- Creates urgency: "How long can I survive past the timer?"
(Source: [VS Wiki - Stages](https://vampire.survivors.wiki/w/Stages), [GameRant](https://gamerant.com/vampire-survivors-30-minutes-reaper-boss-death-beat-kill/))

### Comparative Difficulty Approaches

**Vampire Survivors: Time-Based Scaling**
- Difficulty = f(time), independent of player level
- Advantage: Power investment always feels rewarded
- Enemy HP, speed, and spawn rate increase with elapsed time
- Endless mode: +100% base HP, +50% spawn rate, +25% damage per cycle
(Source: [Steam Community](https://steamcommunity.com/app/1794680/discussions/0/3489752656787156939/))

**Brotato: Wave-Based with Shop Breaks**
- 20 waves total, duration 20-60 seconds each
- Mandatory shop breaks between waves prevent mental exhaustion
- Elite and Horde waves create punctuated difficulty spikes
- Players choose their own difficulty through item selection
(Source: [Brotato Wiki](https://brotato.wiki.spellsandguns.com/Waves))

**Halls of Torment: Diablo-Influenced**
- Stage modifiers affect enemy speed, HP, and quantity
- Separate difficulty modes (Normal, Agony I-V)
- Longer runs (~30 min) with more gradual difficulty
- Developers use "spreadsheets to plan how different progressions should play out" combined with gut-feel playtesting
(Source: [FullCleared Interview](https://fullcleared.com/features/inside-halls-of-torment-an-interview-with-chasing-carrots/))

**Deep Rock Galactic: Survivor: Performance-Based (Anti-Pattern)**
- Killing faster triggers the drop pod sooner, meaning less time for resources
- Players reported this as "punishing success" -- a design anti-pattern for the genre
- The community feedback: "Rather than having build-ups and releases that prevent player overwhelm, the game uses a 'shake a cola can until it explodes' approach"
(Source: [Steam Community](https://steamcommunity.com/app/2321470/discussions/0/591782690120891126/))

### Managing Tension: Key Principles

1. **Peaks and valleys, not constant escalation**: The best VS-likes alternate between moments of danger and moments of dominance. Constant escalation creates exhaustion, not excitement.

2. **The player should feel overwhelmed twice**: Once in the crisis point (minutes 10-15) before evolutions save them, and once at the finale (minutes 25-30) as the ultimate challenge. In between should be a power fantasy valley where the player feels rewarded.

3. **Death should feel unfair (slightly)**: The Reaper is unbeatable. This is intentional. The "loss" at 30 minutes isn't failure -- it's the natural end. Players should feel "I could have done more" rather than "I wasn't good enough."

4. **Enemy variety creates texture**: Mad Forest's 11 enemy types create jarring difficulty jumps. Stages with 16-20 enemy types create smoother progression through incrementally stronger enemies.
(Source: [Steam Community](https://steamcommunity.com/app/1794680/discussions/0/4346606879515964572/))

5. **Inverse Mode shows conscious difficulty design**: In VS's Inverse Mode, enemies start with +200% HP and gain +5% HP and +0.5 movement speed per minute. This creates a dramatically different tension curve where early game is harder and late game is relatively easier (because player scaling outpaces the gradual enemy scaling).

---

## 6. Design Principles Summary: What Makes VS-Likes Addictive

### The 7 Core Design Pillars

1. **Compressed Power Fantasy**: Every run is a complete hero journey in 15-30 minutes. Weakness to godhood, every time.

2. **Reward Frequency Over Magnitude**: A reward every ~23 seconds beats a big reward every 2.5 minutes. Many small dopamine hits > few large ones.

3. **Minimal Skill Floor, High Build Ceiling**: Automatic attacks mean anyone can play. Build knowledge creates depth for experienced players.

4. **Exponential Growth Feeling**: Power doesn't grow linearly. Synergies and evolutions create multiplicative jumps that feel incredible.

5. **Loss Without Punishment**: Gold and unlocks persist between runs. No run feels wasted. Every failure teaches and progresses.

6. **Progressive Visual Chaos**: The screen evolves from clean to overwhelmingly busy. Late-game visual chaos IS the reward -- it proves how powerful you've become.

7. **Hidden Systems Encourage Discovery**: Secret evolutions, hidden characters, and unlockable stages create long-term engagement beyond a single run.

### Design Anti-Patterns to Avoid

1. **Catch-up scaling**: Don't scale enemies to player level. Players must feel that power investment pays off.

2. **Too many equal choices**: Level-up menus with 8+ equally-viable options create decision paralysis. 3-4 options is the sweet spot.

3. **Constant escalation without valleys**: Players need moments of dominance between difficulty spikes. The power fantasy IS the game.

4. **Punishing good play**: (DRG:S anti-pattern) Killing faster should benefit the player, never penalize them.

5. **Upgrade menu fatigue**: If level-ups are too frequent with too many meaningful choices, the menu becomes a chore. Solutions: fewer options, auto-select, or batch upgrades.

6. **Linear power growth**: Exponential/multiplicative scaling is what creates the "feels amazing" moment. +5 damage is boring. 2x damage is exciting. Weapon + passive = evolved weapon is thrilling.

---

## 7. Implementation Checklist for Spell Cascade

Based on this research, concrete design targets:

### Reward Timing
- [ ] First level-up within 30-60 seconds of run start
- [ ] Level-ups every ~20 seconds in early game, extending to ~45 seconds by endgame
- [ ] Vacuum/magnet equivalent for "reward avalanche" moments
- [ ] 3-4 upgrade options per level-up (not more)

### Power Curve
- [ ] Enemy scaling based on time elapsed, NOT player level
- [ ] Exponential growth inflection point around 8-10 minutes
- [ ] Spell evolution system (base spell + catalyst = evolved spell)
- [ ] Build completion around minute 20 (6 spell slots filled, upgrades maxed)
- [ ] Meta-progression that reduces early vulnerability without eliminating it

### Visual Feedback
- [ ] Enemy death particles (color-coded per enemy type)
- [ ] XP gem collection trails
- [ ] Screen shake on high-damage hits (toggleable, 0.1s freeze between shake segments)
- [ ] Damage numbers (toggleable)
- [ ] Hit flash on enemies (1-2 frames white flash)
- [ ] Level-up radial burst effect
- [ ] Progressive screen chaos (clean early, visually overwhelming late)

### Difficulty Curve
- [ ] Tension peaks at minutes 5, 10-12, and 25-28
- [ ] Power fantasy valley at minutes 15-22
- [ ] Hard stop at minute 30 (Spell Cascade equivalent of The Reaper)
- [ ] 15-20+ enemy types per stage for smooth difficulty progression
- [ ] Crisis point at minute 10-12 where build viability is tested

### Sound Design
- [ ] Short, layered sound effects that compound into a "symphony"
- [ ] Escalating chest/reward opening jingle (casino-inspired)
- [ ] Distinct level-up fanfare that cuts through gameplay audio
- [ ] Gem collection chime with slight pitch randomization

---

## Sources

### Primary Analysis Articles
- [JB Oger - The Secret Sauce of Vampire Survivors](https://jboger.substack.com/p/the-secret-sauce-of-vampire-survivors) - Detailed design analysis with specific numbers (23-second reward interval, hardcoded chest contents)
- [JB Oger - The Emotions of Rogue-Lites](https://jboger.substack.com/p/the-emotions-of-rogue-lites) - Emotional arc analysis of roguelite runs
- [The Conversation - Gambling Psychology in VS](https://theconversation.com/vampire-survivors-how-developers-used-gambling-psychology-to-create-a-bafta-winning-game-203613) - Academic analysis of casino design techniques
- [Psychology of Vampire Survivors](https://platinumparagon.info/psychology-of-vampire-survivors/) - SDT and flow state analysis
- [Adrian Hon - Brotato Design Analysis](https://adrianhon.substack.com/p/brotato) - Wave timing and shop design
- [KokuTech - Power Fantasy Through Rapid Escalation](https://www.kokutech.com/blog/gamedev/design-patterns/power-fantasy/vampire-survivors) - VS as power fantasy archetype

### Developer Interviews and Postmortems
- [FullCleared - Halls of Torment Interview](https://fullcleared.com/features/inside-halls-of-torment-an-interview-with-chasing-carrots/) - Chasing Carrots on balancing difficulty with spreadsheets and gut feel
- [Game Developer - VS Development](https://www.gamedeveloper.com/design/vampire-survivors-development-sounds-like-an-open-source-fueled-fever-dream) - Luca Galante on open-source tools and development process
- [GameSpot - VS Creator Interview](https://www.gamespot.com/articles/how-vampire-survivors-went-from-hobby-project-to-game-of-the-year/1100-6511980/) - From hobby project to GOTY

### Game Design Fundamentals
- [Vlambeer - The Art of Screenshake](https://theengineeringofconsciousexperience.com/jan-willem-nijman-vlambeer-the-art-of-screenshake/) - Foundational talk on game juice
- [Oreate AI - Screen Shake and Hit Stop Research](https://www.oreateai.com/blog/research-on-the-mechanism-of-screen-shake-and-hit-stop-effects-on-game-impact/decf24388684845c565d0cc48f09fa24) - Specific timing data for hitstop (50-150ms)
- [GameAnalytics - Squeezing Juice](https://www.gameanalytics.com/blog/squeezing-more-juice-out-of-your-game-design) - Overview of juice techniques
- [Blood Moon Interactive - Juice in Game Design](https://www.bloodmooninteractive.com/articles/juice.html) - Comprehensive juice guide

### Wiki Data Sources
- [VS Wiki - Level Up](https://vampire-survivors.fandom.com/wiki/Level_up) - XP curve formula (5 base, +10/+13/+16 per tier)
- [VS Wiki - Stages](https://vampire.survivors.wiki/w/Stages) - Stage timers, enemy scaling, Reaper mechanics
- [VS Wiki - Mad Forest](https://vampire-survivors.fandom.com/wiki/Mad_Forest) - Enemy spawn timeline, stage modifiers
- [Brotato Wiki - Waves](https://brotato.wiki.spellsandguns.com/Waves) - Wave duration data (20s-60s)
- [Soulstone Survivors Wiki - Skill Tree](https://soulstone-survivors.fandom.com/wiki/Skill_Tree) - Meta-progression structure

### Community Analysis
- [Escapist Magazine - Roguelite Power Scaling](https://www.escapistmagazine.com/roguelites-items-power-scale-game-development-vampire-survivors/) - How games balance scaling
- [GamesRadar - VS Genre Analysis](https://www.gamesradar.com/games/action/vampire-survivors-kicked-off-a-game-development-gold-rush-but-has-a-legitimately-new-genre-emerged-between-the-cash-ins/) - Genre evolution
- [DRG:S Pacing Criticism](https://steamcommunity.com/app/2321470/discussions/0/591782690120891126/) - Anti-pattern: punishing good play
