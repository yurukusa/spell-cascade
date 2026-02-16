# Distribution Experiment Design: 20→6→3→1

Date: 2026-02-16
Task: explore-spell-cascade-distribution-experiment-20-6-3-1
Depends: distribution-channel-decision-matrix.md

## Context
Spell Cascade v0.2.4 is live on itch.io (T+5h: 4 views, 2 plays, 140 impressions).
Need to expand distribution to validate if the game can find an audience.
Decision matrix already ranked: CrazyGames > GameDistribution > itch.io(done) > Poki(later).

## 20 Distribution Experiments (brainstorm)

1. CrazyGames Basic Launch (no SDK, 2-week metrics)
2. GameDistribution submit (auto-distribute to 2000+ publishers)
3. Newgrounds upload (classic flash game portal, still active)
4. Kongregate revival check (if accepting HTML5)
5. Reddit r/WebGames post
6. Reddit r/gamedev "Feedback Friday" post
7. Reddit r/indiegaming showcase
8. Show HN post (Hacker News)
9. IndieDB listing
10. GameJolt upload
11. Y8 Games submit
12. Armor Games submit
13. Twitter/X campaign (hashtags: #indiegame #godot #gamedev)
14. Discord game dev servers (share link)
15. HTML5 game aggregator sites (miniclip etc)
16. Product Hunt Game Day
17. Facebook Gaming instant games
18. Telegram game bot integration
19. Steam Next Fest demo
20. Personal website embed + SEO

## Narrowed to 6

### Cut reasons:
- 4 (Kongregate): Essentially dead for new submissions
- 9 (IndieDB): Very low traffic for HTML5 games
- 11 (Y8): Poor discoverability, low revenue share
- 12 (Armor Games): No longer accepting submissions
- 15 (Miniclip): Acquired by Tencent, closed to indie submissions
- 16 (Product Hunt): Wrong audience (tech, not gamers)
- 17 (Facebook): Requires Facebook SDK integration, complex
- 18 (Telegram): Requires Telegram bot API, niche
- 19 (Steam): Requires $100 fee + desktop build + significantly more polish
- 20 (Personal site): No traffic to start
- 5, 6, 7 (Reddit posts): Merge into single "Reddit" experiment
- 14 (Discord): Merge into social media outreach

### Kept:
1. **CrazyGames Basic Launch** — ZIP ready (8MB), 2-week metrics
2. **GameDistribution** — Lowest effort, widest auto-distribution
3. **Newgrounds** — Large active community, accepts HTML5, good for feedback
4. **GameJolt** — Active indie community, no curation barrier
5. **Reddit (r/WebGames + r/indiegaming)** — Direct player acquisition
6. **Show HN** — Developer/hacker audience, potential viral

## Narrowed to 3

### Cut reasons:
- 6 (Show HN): Wrong timing. Game is alpha; HN audience expects polish. Save for v0.3+
- 4 (GameJolt): Lower traffic than alternatives, similar audience to itch.io
- 5 (Reddit): Requires account age/karma for some subreddits, blocked by pending_for_human

### THE THREE:
1. **CrazyGames Basic Launch** — Already prepped (ZIP ready)
   - EFFORT: Submit form only (~30min with CDP)
   - METRICS: 2-week data collection by platform
   - RISK: Low. If rejected, feedback on what to improve
   - EXPECTED: 500-5000 plays in 2 weeks (their homepage feature)

2. **GameDistribution** — Submit and forget
   - EFFORT: Create account + upload ZIP (~30min)
   - METRICS: Dashboard shows plays/revenue across publishers
   - RISK: Very low. Auto-distributes to partner sites
   - EXPECTED: Unknown but passive distribution to 2000+ sites

3. **Newgrounds** — Community feedback + exposure
   - EFFORT: Create account + upload (~30min) + write description
   - METRICS: Views, ratings, reviews, favorites
   - RISK: Low. Community is honest but constructive
   - EXPECTED: 100-1000 plays, direct player feedback (reviews)

## THE ONE (first experiment to run)

**CrazyGames Basic Launch**

Reasons:
1. **ZIP already prepared** (8MB, pre-submission checklist done)
2. **Guaranteed visibility** (48h homepage placement for new games)
3. **Built-in analytics** (they track everything: plays, session length, retention)
4. **Path to revenue** (if Basic metrics are good → Full Launch invitation with ads)
5. **No account creation needed** (Google auth available)
6. **Professional feedback** (if rejected, they tell you exactly why)

This is the highest-signal experiment: CrazyGames has the most structured
onboarding for new games, and the metrics they provide are exactly what we
need to decide if Spell Cascade has audience-market fit.

## Experiment Protocol

1. Submit to CrazyGames → wait for approval (1-2 weeks)
2. While waiting: submit to GameDistribution (parallel track)
3. After CrazyGames data: decide if Newgrounds is worth the effort
4. All three feed into Poki readiness assessment

## Success Criteria (per experiment)
| Metric | Threshold | Signal |
|--------|-----------|--------|
| Plays | >100 in first week | "Game is findable" |
| Avg session | >3 min | "Game is engaging" |
| Return rate | >10% | "Game has hooks" |
| Rating | >3.5/5 | "Game is acceptable quality" |
