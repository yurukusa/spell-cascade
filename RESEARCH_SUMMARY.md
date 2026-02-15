# itch.io Discoverability Research - Summary for Spell Cascade

**Research Date**: February 16, 2026
**Game**: Spell Cascade (10-minute roguelike survival with deckbuilding)
**Goal**: Maximize discoverability and downloads on itch.io

---

## Key Findings by Category

### 1. TAGS & SEARCH

**Finding**: Accurate tagging is THE primary discoverability lever.
- itch.io has ~170 curated "top tags" designed for discoverability
- Tags with 10,000+ games are crowded and ineffective unless your game stands out
- Irrelevant tags attract wrong audience → poor conversion → potential account impact

**For Spell Cascade**:
- Use 7-10 tags from: `roguelike`, `survival`, `deckbuilding`, `fast-paced`, `horde-survival`, `action`, `browser`, etc.
- Avoid generic tags (e.g., "indie", "casual") unless critical
- Research competitors: Check top 10 games in "roguelike + survival" space for tag patterns
- Use itch.io's tag autocompleter to stay within curated tags

**Impact**: Tags determine who sees your game in browse, search, and recommendations. This is foundational.

---

### 2. DESCRIPTION & COPY

**Finding**: Visuals do 80% of the work; copy fills gaps.

**Short Description** (2 sentences):
- Must hook immediately: "What will I do?" not "A game about..."
- Example: "Survive 10 minutes against endless enemies by building synergies in your spell deck."
- No long preamble.

**Full Description**:
- Use `##` headers to create sections (Features, How to Play, Credits, etc.)
- Scannable, not a wall of text
- Include controls (WASD/Mouse/Gamepad)
- Highlight unique mechanics first

**Why it matters**: Players browse at 3 seconds per game. Description is for people already interested.

---

### 3. SCREENSHOTS & VISUALS

**Finding**: Browser-playable games with good visuals get 37% play rates. Download-only? 6%.

**Recommendation**: 4 screenshots total
1. Gameplay overview (enemies, spells, UI visible)
2. Deckbuilding interface (unique mechanic showcase)
3. Early vs late game comparison (progression)
4. Polish moment (end-of-run screen or visual highlight)

**Best Practices**:
- Vary composition and scene
- Include UI (players want to see what they're playing)
- 1280px width minimum
- Static images more scannable than GIFs (though GIFs work too)

**Current State**: Spell Cascade has 1 gameplay GIF. Need 3 more.

---

### 4. BROWSER PLAYABILITY

**Finding**: Critical for discoverability and conversion.

**Impact**:
- Browser games: 37% click-to-play rate
- Download-only games: 6% click-to-play rate

**Spell Cascade advantage**: Already has HTML5 build. Just needs proper upload configuration.

**Technical Checklist**:
- ✅ Mark file as "This file will be played in the browser"
- ✅ index.html in ZIP root (not subfolder)
- ✅ < 1,000 files, < 500MB total, no single file > 200MB
- ✅ Test in multiple browsers before launch

---

### 5. RELEASE STATUS ("In Development" vs "Released")

**Finding**: Status field is a filter, NOT a discoverability booster.

**Impact**:
- No penalty for "In Development"
- No visibility bump when transitioning to "Released"
- Just a label for browsing filters

**For v0.2 Spell Cascade**: Set to "Released" (implies stable, feature-complete).

**Important**: If you want visibility for updates, use devlogs (they get indexed), not status changes.

---

### 6. GENRE SELECTION

**Finding**: Genre is mandatory for recommendation algorithms. Better to pick one primary than leave blank.

**For Spell Cascade**:
- Primary: `Action` (broader reach, ~13,000 views for median action games)
- Or: `Roguelike` (smaller but highly targeted audience)
- Best case: Both if itch.io allows multiple

**Data**: Top-performing games tend to be Action, Platformer, or Interactive Fiction. Roguelike is growing but niche.

---

### 7. DEVLOGS

**Finding**: Devlogs are free, indexed marketing. Post them for major milestones.

**Launch Devlog**:
- Post on release day (same day as page publish)
- 3-5 paragraphs: Thank you + story + what it is + features + how to play + CTA
- Include a screenshot/GIF
- Links: Direct game link, controls, playtime

**Ongoing**:
- Post 1-2 per month during active development
- Topics: New features, bug fixes, behind-the-scenes, feedback responses
- Shows project is alive → builds audience → sustained discoverability

**Spam Warning**: Posting 12 devlogs in 6 days can trigger spam filters. Avoid.

---

### 8. NAMING & PRICING ("Name Your Price" vs "Free" vs "Paid")

**Finding**: Name Your Price (PWYW) is sweet spot for indie games on itch.io.

**Impact**:
- **Free games**: Highest raw discoverability (filtered for "free"), but no revenue
- **PWYW**: Slightly lower discoverability than "Free" but captures donations, higher conversion
- **Paid**: Lowest discoverability, but those who buy = committed audience

**For Spell Cascade**: PWYW with $0 minimum and $1 default
- Barrier-free play → higher click rate
- Default suggestion captures ~10-20% of engaged players
- Word-of-mouth spreads more easily (free barrier)

**Data**: PWYW games often earn more money because trial converts better than sticker price.

---

### 9. TIMING & LAUNCH STRATEGY

**Finding**: Timing matters, but it's about avoiding crowding, not a magic time.

**Best Days**: Tuesday-Thursday
**Best Times**: 11 AM or 3 PM (US timezone)
**Avoid**: Weekends (too many launches, buried fast)

**Critical Rule**: Publish page + upload files **at the same time**
- itch.io placement in "Recent" is based on page publish date
- Don't create page early and upload later (wasted visibility boost)

**Post-Launch (Week 1)**:
- Day 1: Monitor comments, fix critical bugs
- Days 2-3: Respond to feedback, share on social
- Days 4-7: Post update devlog if you made fixes, thank players

---

### 10. COMMENTS & COMMUNITY

**Finding**: Comments don't boost discoverability (no rating/voting system), but they build engagement.

**Recommendation**: Enable comments, NOT discussion board (simpler management).

**Why it matters**:
- Player feedback = content for updates = more devlogs = more visibility
- Engaged players become repeat visitors and word-of-mouth marketers
- Shows game is actively maintained

**Best Practice**: Respond to all first-week comments (24 hours max). Build loyalty.

---

### 11. FILE SIZE & DISTRIBUTION

**Finding**: Larger file = lower download rates. Optimize.

**Limits**:
- Total files < 1,000
- Total size < 500MB
- Single file < 200MB

**For Spell Cascade**:
- HTML5 build should be optimized for web (gzip, minified assets)
- Windows build should be reasonably sized (< 200MB preferred)

---

### 12. Content Creator Quality Guidelines (itch.io Official)

**Must Have**:
- Playable game (browser or download)
- Cover image
- At least 3 screenshots
- Genre selected
- Basic description

**Should Have**:
- 5-10 accurate tags
- Launch devlog
- Comments enabled
- Social media links

**Nice to Have**:
- Multiple screenshots (5-10)
- Multiple formats (browser + download)
- Behind-the-scenes content (art, music, process)
- Regular updates + devlogs

---

## Academic Research: What Makes Games Successful on itch.io

Research from University of Alberta (2024) found:

1. **Multi-platform support** matters (Windows + browser = advantage)
2. **Genre selection** is critical for algorithmic recommendation
3. **Quality descriptions** correlate with higher rankings
4. **Puzzle, Platformer, Interactive Fiction, Action** genres rank highest
5. **Better tagging systems needed** (current itch.io tags lack standardization)

**Implication for Spell Cascade**: Multi-platform (✅ has both) + solid description + accurate genre/tags = good foundation.

---

## Spell Cascade Competitive Advantages

1. **Browser-playable**: 37% engagement vs 6% for download-only
2. **Unique mechanic**: Deckbuilding in survival space = differentiator
3. **10-minute runtime**: Fits "quick play" trend, low friction entry
4. **Name Your Price**: Perfect for indie, captures donations
5. **Visual polish**: (Verify from game) GIF + screenshots should showcase this

---

## Risk Areas to Monitor

1. **Tag accuracy**: If tags don't match gameplay, algorithm will downrank after initial few clicks
2. **Browser performance**: If HTML5 build is slow/buggy, 37% engagement rate collapses
3. **Description mismatch**: If description promises deckbuilding but gameplay is shallow, player churn
4. **Low engagement post-launch**: If no comments/activity, algorithm treats as "dead" game
5. **No follow-up updates**: Single-version games plateau. Updates = new devlogs = re-engagement

---

## Recommended Action Order

### Pre-Publish (1-2 days before)
1. [ ] Finalize 7-10 tags (accuracy first)
2. [ ] Write 2-sentence hook + full description with headers
3. [ ] Add 3 screenshots (variety, gameplay focus, deckbuilding, progression)
4. [ ] Verify cover image is 630x500px and visually strong
5. [ ] Test HTML5 build in Chrome, Firefox, Safari
6. [ ] Test Windows build on clean machine
7. [ ] Write launch devlog (but don't post yet)
8. [ ] Pick publish date/time (Tue-Thu, 11 AM or 3 PM)

### Publish Day
1. [ ] Upload HTML5 build (mark as browser-playable)
2. [ ] Upload Windows build (optional but recommended)
3. [ ] Set genre, pricing, all metadata
4. [ ] Enable comments
5. [ ] **Publish page + files simultaneously** (not separately!)
6. [ ] Post launch devlog
7. [ ] Share link on 1-2 platforms (Twitter, Discord)

### Week 1
1. [ ] Monitor comments 24/7 (respond all within 24 hours)
2. [ ] Fix any critical bugs immediately
3. [ ] Note feedback themes
4. [ ] Post update devlog if fixes made
5. [ ] Thank players publicly

### Ongoing
1. [ ] Post devlog for each major update (1-2 per month)
2. [ ] Maintain comment responsiveness (< 24 hours)
3. [ ] Monitor itch.io dashboard (views, plays, downloads)
4. [ ] Watch for emerging bugs in community feedback

---

## Sources

All research is drawn from:
- Official itch.io documentation (Creators Guild)
- Community discussions (itch.io forums, 2024-2026)
- Academic research (University of Alberta, 2024)
- Industry guides (How To Market A Game, GDevelop, Cinevva)
- Creator case studies (arimia, Medium, Reddit)

No single "secret sauce" for discoverability exists. Success is a combination of:
1. Accurate metadata (tags, genre)
2. Strong visuals (cover, screenshots)
3. Clear messaging (description)
4. Technical excellence (browser + download, no bugs)
5. Community engagement (comments, devlogs, updates)
6. Timing strategy (avoid weekends, avoid spamming)

Spell Cascade has a good foundation. Execution on these fundamentals will maximize launch impact.
