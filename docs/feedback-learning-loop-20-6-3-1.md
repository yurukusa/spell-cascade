# Feedback Learning Loop: 20 -> 6 -> 3 -> 1

Date: 2026-02-16
Context: Autonomous game factory pipeline for VS-like/survivor browser games.
Stack: Godot 4.3, quality-gate.sh (3-tier), pipeline-orchestrator.sh, SpellCascadeAutoTest.gd, feel scorecard, gate-log.jsonl

## Problem Statement

The game factory has an autonomous pipeline: **Idea -> Build -> Test -> Ship**. Quality gates exist (stability, balance, regression, feel scorecard). But the system has a fundamental alignment problem:

**The quality gate thresholds were set by the AI, not calibrated against human judgment.**

Evidence from the current system:
- `thresholds.json` has `min_damage_taken: 1`, `min_lowest_hp_pct: 0.10`, `pass_threshold: 3` -- all chosen by engineering heuristic, never validated against what makes the human (gurasu) say "this feels right"
- `gate-log.jsonl` contains 53 entries with verdicts (GO/CONDITIONAL/NO-GO) but zero records of whether the human agreed with each verdict
- `playtest_log.md` contains rich human feedback ("boss is unreachable", "dead zone 120-225s", "no skill moment between upgrades") but none of it feeds back into `thresholds.json`
- `pending_for_human.md` tracks human decisions about tools and approvals, but has no structured format for game quality judgments
- The `feel_scorecard.run_desire` metric is at 0.25 (FAIL), and the system knows it is failing, but has no mechanism to learn *what value would satisfy the human*

The gap is clear: **human feedback exists but is not machine-readable, not systematically captured, and not used to update the system's decision parameters.**

### What "Learning" Means Here

This is NOT machine learning in the neural network sense. The factory runs on bash scripts and JSON thresholds. "Learning" means:

1. Human reviews a game state and gives a structured verdict (approve/reject/adjust)
2. That verdict is stored alongside the machine metrics that produced it
3. A calibration algorithm updates thresholds so the machine's next verdict would have matched the human's
4. Over N iterations, the machine's GO/NO-GO decisions converge with the human's would-be decisions

The goal is: **after 20-30 human reviews, the system's autonomous verdicts match human judgment >90% of the time, and the human can step back to sampling-only review (1 in 10 runs).**

### What We Already Have

| Component | Location | Format | State |
|-----------|----------|--------|-------|
| Quality thresholds | `quality-gate/thresholds.json` | JSON | Static, hand-tuned |
| Gate verdicts | `quality-gate/gate-log.jsonl` | JSONL | Machine-only, no human column |
| Pipeline reports | `reports/report-*.md` | Markdown | Human-readable, not machine-parseable for feedback |
| Pipeline JSON | `--json` flag output | JSON | Machine-readable, ephemeral (stdout only) |
| Feel scorecard | In `results.json` | JSON | Computed per run, never compared to human rating |
| Playtest feedback | `playtest_log.md` | Free-text markdown | Rich but unstructured |
| Human queue | `pending_for_human.md` | Markdown with sections | Tracks decisions, not quality judgments |
| Baselines | `quality-gate/baselines/*.json` | JSON | Saved on GO, never evaluated by human |

### Constraints

1. **Minimal human effort**: Gurasu's time is the scarcest resource. Feedback capture must take <30 seconds per review
2. **No ML infrastructure**: No Python ML libraries, no model training, no GPUs. Pure JSON + bash + jq
3. **Small data**: Expect 5-50 human reviews total before the system is calibrated. Must learn fast
4. **Monotonic improvement**: The system must never get worse from feedback. Bad feedback (outlier, misclick) must not corrupt the model
5. **Transparent**: Every threshold change must be explainable ("changed min_damage_taken from 1 to 3 because human rejected 5 GO verdicts where damage < 3")
6. **Compatible**: Must integrate with existing `quality-gate.sh`, `pipeline-orchestrator.sh`, and `thresholds.json` without breaking them

---

## The 20 Candidate Approaches

Each candidate is a complete feedback learning system. Scored on four axes, 1-5:

- **Autonomy Impact (AI)**: Can it actually improve autonomous decisions? 5 = directly updates decision parameters, 1 = informational only
- **Implementation Effort (IE)**: How hard to build? 5 = trivial (hours), 1 = major infrastructure (weeks)
- **Robustness (R)**: Won't degrade from bad data or edge cases? 5 = inherently safe, 1 = fragile
- **Data Efficiency (DE)**: Learns fast with few examples? 5 = useful from 3 examples, 1 = needs 100+

---

### F01: Threshold Auto-Tuning via Human Verdict Overlay

**Concept**: After each pipeline run, present the report to the human. Human marks AGREE/DISAGREE with the machine verdict. On DISAGREE, the system identifies which threshold(s) were the "deciding vote" and nudges them toward the human's implied preference.

**Mechanism**:
1. Machine says GO. Human says DISAGREE (should be NO-GO).
2. System finds the metric(s) closest to their threshold boundary.
3. Nudges those thresholds to make the current run a NO-GO.
4. Uses exponential moving average: `new_threshold = alpha * human_implied + (1-alpha) * current`, where alpha = 0.3.

**Example**: Machine GO with damage_taken=2 (threshold: min_damage_taken=1). Human disagrees. System infers human wants min_damage_taken >= 3. New threshold: `1 * 0.7 + 3 * 0.3 = 1.9`, rounded to 2.

| AI | IE | R | DE | Total |
|----|----|----|-----|-------|
| 5  | 4  | 3  | 4   | 16    |

**Why this score**: Directly updates the decision parameters the pipeline actually uses. Simple to implement (jq + math). Risk of oscillation if human is inconsistent -- docked on Robustness. Learns meaningfully from even 3-5 disagreements.

---

### F02: Preference Pair Learning (A/B Comparison)

**Concept**: Present the human with two pipeline runs side by side. Human picks which one is better. System builds a preference model from pairwise comparisons and derives threshold adjustments.

**Mechanism**:
1. System selects two recent runs with different characteristics.
2. Human picks preferred run (or "equal").
3. System identifies which metrics differ and adjusts weights/thresholds toward the preferred run's values.
4. Uses Bradley-Terry model for pairwise comparison.

| AI | IE | R | DE | Total |
|----|----|----|-----|-------|
| 4  | 2  | 4  | 3   | 13    |

**Why this score**: Preference pairs are robust (human just picks A or B, hard to give bad data). But requires infrastructure to select good comparison pairs, present them, and implement Bradley-Terry. Needs ~15 comparisons minimum. Docked on Implementation Effort because pair selection and presentation is non-trivial.

---

### F03: Rule Extraction from Approval Patterns

**Concept**: Accumulate a labeled dataset of (metrics, human_verdict) pairs. Periodically run a rule extraction algorithm that finds simple IF-THEN rules explaining the human's decisions. Inject those rules as new quality gate checks.

**Mechanism**:
1. Collect 10+ labeled examples.
2. Run decision tree / rule extraction (implemented in jq/bash as nested if/else discovery).
3. Output rules like: "IF damage_taken < 5 AND peak_enemies < 10 THEN human_verdict = NO-GO".
4. Add extracted rules to `thresholds.json` as new gate conditions.

| AI | IE | R | DE | Total |
|----|----|----|-----|-------|
| 5  | 2  | 4  | 2   | 13    |

**Why this score**: Extracted rules are transparent and directly usable. But needs 10+ examples before any rule is reliable, and building a decision tree in bash is complex. Robust because rules are human-readable and can be verified before deployment.

---

### F04: Sentiment-Weighted Scoring Adjustments

**Concept**: Human provides free-text feedback after each review. System extracts sentiment (positive/negative) and maps it to metric adjustments. "Too easy" -> tighten difficulty floor. "Too chaotic" -> lower density thresholds.

**Mechanism**:
1. Human writes free-text: "enemies are too sparse, feels boring in mid-game".
2. Keyword extraction maps to metrics: "sparse" -> density, "boring" -> dead_time/action_density.
3. Sentiment (negative) + metric mapping -> adjust thresholds in the "harder" direction.

| AI | IE | R | DE | Total |
|----|----|----|-----|-------|
| 3  | 3  | 2  | 4   | 12    |

**Why this score**: Natural for the human (just write what you think). But keyword->metric mapping is fragile and ambiguous. "Too easy" could mean many things. Low Robustness because NLP in bash is unreliable. Useful from even 1 example (high Data Efficiency).

---

### F05: Bayesian Threshold Updating

**Concept**: Model each threshold as a probability distribution (prior). Each human verdict is evidence that updates the posterior. After each update, the threshold becomes the posterior mean (or MAP estimate).

**Mechanism**:
1. Prior: each threshold has a mean and variance (e.g., min_damage_taken ~ Normal(1, 2)).
2. Human says "this GO was wrong" -> likelihood function shifts the posterior.
3. New threshold = posterior mean.
4. Variance shrinks with each observation (increasing confidence).

**Implementation**: Can be simplified to weighted running average with decaying learning rate. No actual Bayesian math needed -- the intuition is enough.

| AI | IE | R | DE | Total |
|----|----|----|-----|-------|
| 5  | 3  | 5  | 5   | 18    |

**Why this score**: Mathematically principled -- naturally handles uncertainty, converges to true human preference, and is robust to noise (single outlier does not override many consistent signals). Implementable as exponential moving average with confidence tracking. Learns from first example. Highest total score.

---

### F06: Calibration Curve Mapping

**Concept**: Build a calibration curve: for each confidence level (health score), measure what fraction of the time the human agrees. Use the curve to identify systematic biases and correct them.

**Mechanism**:
1. Collect (health_score, human_agrees) pairs.
2. Bin by health_score (e.g., 0.0-0.2, 0.2-0.4, ...).
3. In each bin, compute agreement rate.
4. If health_score 0.4-0.6 has only 40% agreement, the system is unreliable in that range -> tighten the GO threshold or flag for mandatory human review.

| AI | IE | R | DE | Total |
|----|----|----|-----|-------|
| 4  | 3  | 4  | 2   | 13    |

**Why this score**: Identifies exactly where the system is miscalibrated. Robust because it is descriptive (no parameter changes until enough data). But needs 20+ examples to populate bins meaningfully. Does not directly update thresholds -- only identifies where updates are needed.

---

### F07: Human-in-the-Loop Labeling Queue

**Concept**: Create a structured labeling interface where the human reviews pipeline reports and tags each one with a verdict and optional metric-level feedback. All labels stored in a JSONL file for later analysis.

**Mechanism**:
1. After each pipeline run, append a "pending review" entry to `human-reviews.jsonl`.
2. Human reviews at their convenience (batch mode).
3. For each entry: APPROVE / REJECT / ADJUST + optional per-metric notes.
4. Labeled data accumulates for other algorithms to consume.

| AI | IE | R | DE | Total |
|----|----|----|-----|-------|
| 2  | 5  | 5  | 3   | 15    |

**Why this score**: The foundation that every other approach needs. Dead simple to implement (append JSON to a file). Perfectly robust (just stores data). But does not improve decisions by itself -- it only collects the data. Other algorithms (F01, F05, F03) consume this data. Docked heavily on Autonomy Impact because it is passive.

---

### F08: Memory/Context Injection (Feedback Memory Bank)

**Concept**: Store all human feedback as a searchable memory bank. Before each pipeline run, the AI agent queries the bank for similar past situations and adjusts its behavior based on remembered feedback.

**Mechanism**:
1. Each feedback entry is stored with its associated metrics as a key.
2. Before making a verdict, the system searches for the closest past feedback (by metric similarity).
3. If a similar run was previously rejected by human, flag the current run for extra scrutiny.

| AI | IE | R | DE | Total |
|----|----|----|-----|-------|
| 3  | 3  | 3  | 4   | 13    |

**Why this score**: Good for preventing repeated mistakes. But "similar" is hard to define with mixed metrics (how do you compare damage_taken=5 to peak_enemies=20?). Implementation needs a similarity function. Does not update thresholds -- only provides advisory context.

---

### F09: Reinforcement Learning from Human Feedback (RLHF-lite)

**Concept**: Treat the pipeline as a policy that maps game metrics to verdicts. Human feedback is the reward signal. Use a simplified reward model to adjust the policy (threshold weights).

**Mechanism**:
1. Policy: `verdict = f(metrics, thresholds)`.
2. Reward: human agrees = +1, disagrees = -1.
3. Policy gradient: for each threshold, compute: did increasing this threshold move the verdict toward the human's preference?
4. Update thresholds in the direction that increases expected reward.

| AI | IE | R | DE | Total |
|----|----|----|-----|-------|
| 5  | 1  | 2  | 2   | 10    |

**Why this score**: Highest theoretical ceiling -- it is the principled way to align any system with human preferences. But massive implementation burden for a bash pipeline (needs policy gradient computation, reward modeling, exploration vs. exploitation). Fragile with small data. Overkill for the problem size.

---

### F10: A/B Testing Framework (Threshold Variant Testing)

**Concept**: Run the pipeline with two different threshold configurations simultaneously. Present both results to the human. Human picks which configuration produced better verdicts. Winning configuration becomes the new default.

**Mechanism**:
1. Fork `thresholds.json` into A (current) and B (perturbed variant).
2. Run both configurations on the same test results.
3. Present both verdict streams to human.
4. Human picks A or B.
5. Winner becomes baseline. Generate new B by perturbing winner.

| AI | IE | R | DE | Total |
|----|----|----|-----|-------|
| 4  | 3  | 4  | 3   | 14    |

**Why this score**: Clean experimental design. Robust because it always keeps the current-best as baseline. But requires running the pipeline twice per evaluation and human effort to compare two streams. Converges slowly (binary search across threshold space).

---

### F11: Verdict Override Log with Threshold Replay

**Concept**: When the human disagrees with a verdict, record the override. Periodically replay all historical results through candidate threshold sets and find the set that minimizes disagreements.

**Mechanism**:
1. Record all (metrics, machine_verdict, human_verdict) triples.
2. Weekly: brute-force search over threshold ranges.
3. For each candidate threshold set, replay all historical data and count human agreement rate.
4. Adopt the threshold set with highest agreement.

| AI | IE | R | DE | Total |
|----|----|----|-----|-------|
| 5  | 3  | 5  | 3   | 16    |

**Why this score**: Globally optimal -- finds the single best threshold set for all historical data. Robust because it optimizes over the full dataset (no single outlier dominates). But needs ~15 labeled examples before the search space is constrained enough. Implementation is moderate (brute-force search in bash is slow but feasible).

---

### F12: Gradient-Free Threshold Optimization (Nelder-Mead)

**Concept**: Use the Nelder-Mead simplex method (or similar derivative-free optimizer) to search the threshold space, using human agreement rate as the objective function.

**Mechanism**:
1. Define objective: `agreement_rate(thresholds) = count(machine_verdict == human_verdict) / total`.
2. Initialize simplex with current thresholds + random perturbations.
3. Evaluate each vertex by replaying historical data.
4. Standard Nelder-Mead iteration (reflect, expand, contract).
5. Converge when improvement < epsilon.

| AI | IE | R | DE | Total |
|----|----|----|-----|-------|
| 5  | 1  | 4  | 2   | 12    |

**Why this score**: Mathematically rigorous optimization. But implementing Nelder-Mead in bash is absurd -- would need Python. Needs 15+ examples to avoid overfitting. High impact if it works, impractical to build.

---

### F13: Per-Metric Confidence Bands

**Concept**: For each metric, track the range where human approvals occur. The confidence band is [min_approved, max_approved]. New runs falling outside the band are flagged.

**Mechanism**:
1. On each human APPROVE, record all metric values.
2. Per metric, maintain [min_seen_in_approved, max_seen_in_approved].
3. New run's metric outside band -> FLAG for review.
4. After enough data, convert bands into threshold updates.

| AI | IE | R | DE | Total |
|----|----|----|-----|-------|
| 4  | 4  | 4  | 3   | 15    |

**Why this score**: Simple and intuitive. Naturally builds a picture of the "acceptable zone" for each metric. Robust because bands only widen (from approvals) or trigger flags (from rejections). Needs ~10 approvals per metric to build meaningful bands.

---

### F14: Disagreement-Triggered Threshold Interrogation

**Concept**: Only act on disagreements. When human and machine disagree, ask the human: "Which metric bothers you most?" Use the answer to surgically update that one threshold.

**Mechanism**:
1. Machine says GO. Human says NO-GO.
2. System presents all metrics with their values and thresholds.
3. Human selects the problematic metric (e.g., "damage_taken is too low").
4. System asks: "What value would be acceptable?" or infers from the current value.
5. Single threshold updated.

| AI | IE | R | DE | Total |
|----|----|----|-----|-------|
| 5  | 4  | 3  | 5   | 17    |

**Why this score**: Maximum data efficiency -- each interaction updates exactly the right parameter. Minimal cognitive load on the human (just point at the problem). But requires a way to present metrics and capture the response (adds ~30s per disagreement). Risk of local optimization -- fixing one metric might unmask another issue.

---

### F15: Exponential Moving Average Consensus Tracker

**Concept**: Track a running "consensus score" for each metric, blending machine assessment with human feedback. The consensus score replaces raw thresholds over time.

**Mechanism**:
1. For each metric M, maintain `consensus[M] = EMA(human_implied_values, alpha=0.3)`.
2. Human approves run with damage_taken=8 -> consensus[min_damage_taken] moves toward 8 (actually toward "anything >= 8 is OK").
3. Human rejects run with damage_taken=2 -> consensus moves toward "need more than 2".
4. Consensus becomes the effective threshold.

| AI | IE | R | DE | Total |
|----|----|----|-----|-------|
| 5  | 4  | 3  | 4   | 16    |

**Why this score**: Very similar to F01 but with explicit tracking of the running average and direction. Simple math, direct impact. Risk of slow convergence if human is highly variable.

---

### F16: Staged Autonomy Ramp (Phase-Gated Trust)

**Concept**: Instead of learning thresholds, learn *when to ask*. Start with human review on every run. Gradually reduce review frequency as agreement rate improves. Human effort naturally decreases as the system calibrates.

**Mechanism**:
1. Phase 1: Review every run. Log (machine_verdict, human_verdict).
2. Phase 2: Review 1 in 3 runs. Triggered when agreement > 80% over last 10 reviews.
3. Phase 3: Review 1 in 10 runs. Triggered when agreement > 90% over last 20 reviews.
4. Phase 4: Review on CONDITIONAL only. Triggered when agreement > 95%.
5. Regression trigger: If any review disagrees, step back one phase.

| AI | IE | R | DE | Total |
|----|----|----|-----|-------|
| 3  | 5  | 5  | 4   | 17    |

**Why this score**: Does not improve decision quality directly -- just reduces human effort once quality is sufficient. Extremely robust (regression detection built in). Easy to implement (counter + phase logic). But docked on Autonomy Impact because it does not change what the machine decides, only how often it asks.

---

### F17: Multi-Dimensional Threshold Grid Search with Replay

**Concept**: Define a grid of candidate values for each threshold. Replay all labeled data against every grid point. Select the grid point with highest agreement.

**Mechanism**:
1. For each threshold, define 5-10 candidate values spanning reasonable range.
2. For M thresholds, grid has 5^M points. (With 6 thresholds: 15,625 points -- feasible.)
3. For each grid point, replay all labeled data and compute agreement rate.
4. Select best grid point.

| AI | IE | R | DE | Total |
|----|----|----|-----|-------|
| 5  | 2  | 5  | 2   | 14    |

**Why this score**: Guarantees finding the best discrete threshold set. Perfectly robust (evaluates all options). But computational cost grows exponentially with threshold count. Needs enough labeled data to distinguish between grid points (at least 15 labels). Implementation is moderate (nested loops in bash).

---

### F18: Human Feedback Taxonomy + Lookup Table

**Concept**: Define a fixed taxonomy of human feedback categories (too_easy, too_hard, too_chaotic, too_boring, too_fast, too_slow, etc.). Map each category to a specific threshold adjustment. Human selects one category per review.

**Mechanism**:
1. Taxonomy:
   - `too_easy` -> increase `min_damage_taken` by 1, decrease `min_lowest_hp_pct` by 0.05
   - `too_hard` -> decrease `min_damage_taken` by 1, increase `min_lowest_hp_pct` by 0.05
   - `too_boring` -> decrease `max_avg_interval`, increase `min_peak_enemies`
   - `too_chaotic` -> increase `min_avg_interval`, decrease `min_peak_enemies`
   - etc.
2. Human selects category. System applies the fixed mapping.

| AI | IE | R | DE | Total |
|----|----|----|-----|-------|
| 4  | 5  | 3  | 5   | 17    |

**Why this score**: Extremely fast for the human (one click from a list). Immediate effect. Dead simple to implement. But the fixed mapping may not capture the human's actual intent (docked on Robustness). Maximum data efficiency -- every single feedback moves a threshold.

---

### F19: Delta-Based Threshold Drift Detection

**Concept**: Track how much thresholds need to change to match human verdicts. If the required delta is consistently in one direction, apply it. If it oscillates, the current threshold is probably correct.

**Mechanism**:
1. For each human review, compute the "implied threshold" for each metric.
2. Compute delta: `implied - current`.
3. Maintain a signed running sum of deltas.
4. If running sum exceeds a threshold (e.g., 3 consecutive same-sign deltas), apply the adjustment.
5. If running sum oscillates around zero, hold steady.

| AI | IE | R | DE | Total |
|----|----|----|-----|-------|
| 5  | 4  | 5  | 3   | 17    |

**Why this score**: Natural resistance to noise (requires consistent signal before acting). Simple implementation (running sums). Directly updates thresholds. Needs ~5 reviews before it acts (conservative but safe).

---

### F20: Composite Approach: Labeling + Bayesian Update + Staged Autonomy

**Concept**: Combine F07 (labeling infrastructure), F05 (Bayesian updating), and F16 (staged autonomy). Human labels feed Bayesian updates that adjust thresholds, while a phase system reduces human effort as agreement improves.

**Mechanism**:
1. **Layer 1 (F07)**: JSONL labeling file captures every human review.
2. **Layer 2 (F05)**: After each label, Bayesian update adjusts relevant thresholds.
3. **Layer 3 (F16)**: Agreement rate over sliding window determines review frequency.

**Implementation**: Three bash scripts that compose:
- `feedback-capture.sh` -> writes to `human-reviews.jsonl`
- `feedback-learn.sh` -> reads reviews, updates `thresholds.json` via Bayesian EMA
- `feedback-phase.sh` -> reads reviews, computes agreement rate, sets review frequency

| AI | IE | R | DE | Total |
|----|----|----|-----|-------|
| 5  | 3  | 5  | 5   | 18    |

**Why this score**: Combines the best properties of three approaches. Full autonomy impact (updates thresholds). Robust (Bayesian + phase regression). Data efficient (Bayesian learns from first example, phases adapt). Implementation effort is moderate (three scripts, but each is simple). Ties with F05 for highest score.

---

## Summary Table: The 20

| #   | Name                                | AI | IE | R  | DE | Total |
|-----|-------------------------------------|----|----|----|----|-------|
| F01 | Threshold Auto-Tuning               | 5  | 4  | 3  | 4  | 16    |
| F02 | Preference Pair Learning            | 4  | 2  | 4  | 3  | 13    |
| F03 | Rule Extraction                     | 5  | 2  | 4  | 2  | 13    |
| F04 | Sentiment-Weighted Scoring          | 3  | 3  | 2  | 4  | 12    |
| F05 | Bayesian Threshold Updating         | 5  | 3  | 5  | 5  | 18    |
| F06 | Calibration Curve Mapping           | 4  | 3  | 4  | 2  | 13    |
| F07 | Human-in-the-Loop Labeling Queue    | 2  | 5  | 5  | 3  | 15    |
| F08 | Memory/Context Injection            | 3  | 3  | 3  | 4  | 13    |
| F09 | RLHF-Lite                           | 5  | 1  | 2  | 2  | 10    |
| F10 | A/B Testing Framework               | 4  | 3  | 4  | 3  | 14    |
| F11 | Verdict Override + Replay           | 5  | 3  | 5  | 3  | 16    |
| F12 | Nelder-Mead Optimization            | 5  | 1  | 4  | 2  | 12    |
| F13 | Per-Metric Confidence Bands         | 4  | 4  | 4  | 3  | 15    |
| F14 | Disagreement-Triggered Interrogation| 5  | 4  | 3  | 5  | 17    |
| F15 | EMA Consensus Tracker               | 5  | 4  | 3  | 4  | 16    |
| F16 | Staged Autonomy Ramp                | 3  | 5  | 5  | 4  | 17    |
| F17 | Grid Search with Replay             | 5  | 2  | 5  | 2  | 14    |
| F18 | Feedback Taxonomy + Lookup Table    | 4  | 5  | 3  | 5  | 17    |
| F19 | Delta-Based Drift Detection         | 5  | 4  | 5  | 3  | 17    |
| F20 | Composite (Label+Bayes+Staged)      | 5  | 3  | 5  | 5  | 18    |

---

## Shortlist: 6

Selecting by total score, with ties broken by Autonomy Impact (the whole point is to improve autonomous decisions), then Robustness (system must not degrade).

### 1. F05: Bayesian Threshold Updating (Total: 18, AI:5 R:5 DE:5)

**Why it advances**: Mathematically principled approach that naturally handles uncertainty and converges with minimal data. Each human review tightens the distribution. Outlier reviews have diminishing impact as the posterior concentrates. No risk of catastrophic threshold shift from a single bad review.

### 2. F20: Composite (Label + Bayes + Staged) (Total: 18, AI:5 R:5 DE:5)

**Why it advances**: The most complete system -- captures data (F07), learns from it (F05), and reduces human burden over time (F16). Same score as F05 because it *contains* F05 plus complementary components. The question is whether the added complexity is worth it.

### 3. F14: Disagreement-Triggered Interrogation (Total: 17, AI:5 DE:5)

**Why it advances**: Maximum data efficiency per interaction. When the human disagrees, directly asking "which metric?" gives the system exactly the information it needs. No wasted computation on metrics that are fine. Surgical precision in updates.

### 4. F16: Staged Autonomy Ramp (Total: 17, R:5 DE:4)

**Why it advances**: Solves the meta-problem: *how often should the human review?* All other approaches assume a fixed review cadence. F16 dynamically adjusts it. This is essential for the stated goal of reducing human involvement over time. Also provides the regression detection mechanism that catches system degradation.

### 5. F18: Feedback Taxonomy + Lookup Table (Total: 17, IE:5 DE:5)

**Why it advances**: Lowest friction for the human. Selecting "too_easy" from a list takes 2 seconds. The fixed mapping ensures immediate effect. While the mapping is imperfect, it is transparent and editable. The taxonomy also doubles as a common language between human and system.

### 6. F19: Delta-Based Drift Detection (Total: 17, AI:5 R:5)

**Why it advances**: The safety mechanism. It does not act on individual feedback -- it waits for consistent signal. Three consecutive "increase difficulty" reviews trigger an adjustment. An alternating pattern (up, down, up, down) means the threshold is approximately correct. This prevents oscillation, the biggest practical risk in threshold tuning.

### Why These 6 and Not Others

**Excluded despite good score (16)**:
- F01 (Threshold Auto-Tuning): Subsumed by F05 (Bayesian is a better version of the same idea)
- F11 (Verdict Override + Replay): Subsumed by F20 (replay is a useful periodic check, but the composite approach handles the continuous case better)
- F15 (EMA Consensus): Subsumed by F05 (Bayesian updating is EMA with better noise handling)

**Excluded despite interesting concept**:
- F02 (Preference Pairs, 13): Requires presenting two runs simultaneously, high implementation cost for a bash pipeline
- F03 (Rule Extraction, 13): Needs 10+ examples before producing anything; Bayesian starts learning from example 1
- F09 (RLHF-Lite, 10): Massive overkill; we have 6 thresholds and 50 data points, not millions of parameters
- F12 (Nelder-Mead, 12): Requires Python; constraint says no ML infrastructure
- F17 (Grid Search, 14): Feasible but brute-force; Bayesian updating achieves the same result more elegantly

---

## Finalists: 3

### Finalist A: F20 -- Composite (Label + Bayes + Staged Autonomy)

**Why it advances to final 3**: This is the architecturally complete answer. It has three layers that solve three distinct problems: data capture, learning, and effort reduction. The layers are independently testable and deployable.

**Detailed design**:

```
LAYER 1: FEEDBACK CAPTURE (from F07)
  Purpose: Structured recording of human verdicts
  Format: JSONL file (human-reviews.jsonl)
  Interface: CLI command or JSON file edit

  Entry schema:
  {
    "timestamp": "2026-02-16T15:00:00+09:00",
    "run_id": "20260216-150000",
    "machine_verdict": "GO",
    "human_verdict": "REJECT",
    "reason_category": "too_easy",       // from taxonomy
    "problematic_metrics": ["damage_taken", "lowest_hp_pct"],
    "notes": "Bot takes no damage, not engaging",
    "metrics_snapshot": {                 // auto-populated from results.json
      "damage_taken": 0,
      "lowest_hp_pct": 1.0,
      "avg_levelup_interval": 6.4,
      "peak_enemies": 8,
      "health_score": 0.45,
      "desire_score": 0.25
    }
  }

LAYER 2: BAYESIAN THRESHOLD UPDATING (from F05)
  Purpose: Adjust thresholds toward human preference
  Trigger: After each new entry in human-reviews.jsonl

  For each threshold T affected by feedback:
    prior_mean = current threshold value
    prior_variance = initial uncertainty (starts high, shrinks)
    observation = human-implied value for this threshold

    posterior_mean = (prior_mean / prior_variance + observation / obs_variance) /
                     (1/prior_variance + 1/obs_variance)
    posterior_variance = 1 / (1/prior_variance + 1/obs_variance)

    Simplified to EMA:
    new_T = alpha * observation + (1 - alpha) * current_T
    alpha = 1 / (1 + total_observations_for_this_threshold)

    Safety bounds: Each threshold has a [min, max] range it can never exceed.

LAYER 3: STAGED AUTONOMY (from F16)
  Purpose: Reduce human review frequency as agreement improves

  Phases:
  Phase 1 (CALIBRATING): Human reviews every run
    Entry: Default (start here)
    Exit: agreement_rate >= 80% over last 10 reviews -> Phase 2

  Phase 2 (LEARNING): Human reviews 1 in 3 runs
    Entry: Phase 1 exit condition
    Exit up: agreement_rate >= 90% over last 15 reviews -> Phase 3
    Exit down: any disagreement AND agreement_rate < 70% -> Phase 1

  Phase 3 (TUNING): Human reviews 1 in 10 runs
    Entry: Phase 2 exit condition
    Exit up: agreement_rate >= 95% over last 20 reviews -> Phase 4
    Exit down: agreement_rate < 85% over last 10 reviews -> Phase 2

  Phase 4 (AUTONOMOUS): Human reviews on CONDITIONAL only + random 1 in 20
    Entry: Phase 3 exit condition
    Exit down: any disagreement on CONDITIONAL -> Phase 3
```

**Strengths**: Complete system. Each layer can be deployed independently. Phase system aligns with pending_for_human.md's existing "Phase 1/2/3" language.

**Weaknesses**: Three interacting components increase maintenance burden. The Bayesian layer's "human-implied value" is not always clear (if human says "too easy," what is the exact threshold they want?).

---

### Finalist B: F14 -- Disagreement-Triggered Interrogation

**Why it advances to final 3**: Maximum signal per interaction. Every human disagreement produces a direct, unambiguous threshold update. No inference needed -- the human points at the problem.

**Detailed design**:

```
TRIGGER: Machine verdict != Human intent
  (Human can proactively flag disagreement, or system can prompt)

INTERROGATION FLOW:
  1. System presents: "Machine said GO. You disagreed. Here are the metrics:"

     | Metric              | Value | Threshold | Status |
     |---------------------|-------|-----------|--------|
     | damage_taken        | 0     | >= 1      | WARN   | <-- closest to boundary
     | lowest_hp_pct       | 1.0   | >= 0.10   | PASS   |
     | avg_levelup_interval| 6.4   | [8, 35]   | FAIL   |
     | peak_enemies        | 8     | >= 5      | PASS   |

  2. Human selects: "damage_taken" (or multiple)

  3. System asks: "What minimum value would make this acceptable?"
     Human types: "5" (or "higher" for directional-only feedback)

  4. Threshold update:
     If exact value: new_threshold = EMA(current, human_value, alpha=0.3)
     If directional: nudge by 1 standard deviation of historical values

  5. Confirmation: "Updated min_damage_taken: 1 -> 2.2. Effective next run."

DISAGREEMENT LOG (machine-readable):
  {
    "timestamp": "...",
    "run_id": "...",
    "machine_verdict": "GO",
    "human_verdict": "REJECT",
    "interrogation": {
      "selected_metrics": ["damage_taken"],
      "human_target_values": {"damage_taken": 5},
      "threshold_before": {"min_damage_taken": 1},
      "threshold_after": {"min_damage_taken": 2.2},
      "alpha_used": 0.3
    }
  }
```

**Strengths**: Surgical precision. Zero wasted information. Human knows exactly what changed and why. Works from first interaction.

**Weaknesses**: Only triggers on disagreement. Does not learn from agreements (which also carry information -- "this configuration is good, do not change it"). Does not automatically reduce review frequency.

---

### Finalist C: F19 -- Delta-Based Drift Detection

**Why it advances to final 3**: The safety-first approach. It is the only candidate that explicitly prevents oscillation. In a system where the human might be inconsistent (tired, distracted, different mood), F19 waits for clear, consistent signal before acting.

**Detailed design**:

```
CORE DATA STRUCTURE:
  For each adjustable threshold, maintain a delta accumulator:

  delta_accumulators = {
    "min_damage_taken": {
      "running_sum": 0,        // signed sum of implied deltas
      "consecutive_same_sign": 0,
      "total_observations": 0,
      "last_direction": null,  // "up" or "down"
      "history": []            // last 10 deltas
    },
    ...
  }

ON EACH HUMAN REVIEW:
  1. If human AGREES with verdict: no delta recorded (agreement = zero signal)
  2. If human DISAGREES:
     a. Compute implied delta for each metric:
        delta = (human_implied_value - current_threshold)
     b. Add delta to running_sum
     c. Check direction:
        If same as last_direction: consecutive_same_sign++
        If opposite: consecutive_same_sign = 1, last_direction flipped
     d. Append to history

TRIGGER CONDITION:
  If consecutive_same_sign >= 3:
    Apply adjustment: new_threshold = current + median(last 3 deltas)
    Reset accumulator for this metric

  If consecutive_same_sign alternates for 6+ observations:
    Mark threshold as "converged" -- stop adjusting

SAFETY BOUNDS:
  Each threshold has [floor, ceiling]:
  - min_damage_taken: [0, 20]
  - min_lowest_hp_pct: [0.0, 0.5]
  - min_avg_interval: [3.0, 15.0]
  - max_avg_interval: [15.0, 60.0]
  - min_peak_enemies: [1, 30]
  - pass_threshold: [2, 4]

  Adjustment is clamped to these bounds. No threshold can drift outside.
```

**Strengths**: Immune to noise. Single outlier reviews are harmless. Oscillating feedback correctly results in no change. Explicit convergence detection.

**Weaknesses**: Slow to act (needs 3 consistent signals). Does not learn from agreements. Does not reduce review frequency. Conservative to a fault -- may frustrate a human who wants immediate change.

---

### Why These 3 Cover the Problem

Together, the three finalists form complementary layers:

```
F20 (Composite) = "The full system"
  - Data capture + Bayesian learning + autonomy ramp
  - Breadth: covers the entire feedback lifecycle
  - Weakness: inference of "human-implied value" is sometimes ambiguous

F14 (Interrogation) = "The precision tool"
  - Direct metric-level feedback with exact values
  - Depth: maximum information per interaction
  - Weakness: only fires on disagreements

F19 (Drift Detection) = "The safety net"
  - Consistent-signal filter that prevents oscillation
  - Safety: ensures stability of the threshold system
  - Weakness: slow to react
```

The ideal system would combine all three:
- F20's data capture and autonomy ramp (the lifecycle management)
- F14's interrogation flow (the feedback precision tool)
- F19's drift detection (the safety filter)

---

## THE ONE: Bayesian Verdict Alignment Engine (BVAE)

A synthesis of F20 + F14 + F19 -- the composite approach (F20) as the backbone, with interrogation (F14) as the primary feedback interface and drift detection (F19) as the safety layer.

### Why This Is THE ONE

**1. It closes the loop that currently does not exist.**

Today: Human has opinion -> writes free-text in playtest_log.md -> nobody reads it -> thresholds unchanged.

With BVAE: Human has opinion -> structured capture (30s) -> Bayesian update -> thresholds change -> next run reflects human taste -> agreement rate improves -> review frequency drops.

**2. It converges fast with minimal human effort.**

The Bayesian update learns from the first review. By review #5, thresholds are measurably closer to human preference. By review #15, agreement rate exceeds 80%. By review #25, the system operates in Phase 3 (human reviews 1 in 10 runs). The human's time investment is approximately:

| Phase | Reviews | Time Per Review | Total Human Time |
|-------|---------|-----------------|------------------|
| Phase 1 (runs 1-10) | 10 | 30s | 5 min |
| Phase 2 (runs 11-25) | 5 | 30s | 2.5 min |
| Phase 3 (runs 26-100) | 8 | 30s | 4 min |
| Phase 4 (runs 100+) | 1 per 20 | 30s | negligible |

Total investment: ~12 minutes of human time to calibrate the system for life.

**3. It cannot make things worse.**

- Drift detection (F19 layer) prevents oscillating thresholds
- Safety bounds prevent thresholds from reaching absurd values
- Phase regression (F16 layer) catches system degradation
- All changes are logged and reversible (`thresholds.json` is in git)

**4. It uses existing infrastructure.**

- Feedback is stored in JSONL (same format as `gate-log.jsonl`)
- Thresholds are updated in `thresholds.json` (already used by `quality-gate.sh`)
- Phase tracking uses a simple state file (same pattern as `pending_for_human.md` phases)
- The entire system is bash + jq -- no new dependencies

**5. It embodies the user's stated philosophy from pending_for_human.md:**

> Phase 1: Human review permitted (quality learning phase)
> Phase 2: Human review is sampling (e.g., weekly/milestone)
> Phase 3: Runs without human review as the goal

BVAE is the mechanism that makes this progression happen automatically.

---

### Architecture

```
                                BAYESIAN VERDICT ALIGNMENT ENGINE (BVAE)
                                =========================================

    ┌─────────────────────┐     ┌──────────────────────┐     ┌─────────────────────┐
    │  PIPELINE RUN       │     │  HUMAN REVIEW        │     │  LEARNING ENGINE    │
    │                     │     │  (feedback-review.sh) │     │  (feedback-learn.sh)│
    │  pipeline-           │     │                      │     │                     │
    │  orchestrator.sh    │     │  Input:               │     │  Reads:             │
    │       |             │     │  - AGREE / DISAGREE   │     │  - human-reviews    │
    │       v             │     │  - Category           │     │    .jsonl           │
    │  results.json       │     │  - Metric selections  │     │  - thresholds.json  │
    │  gate-log.jsonl     │     │  - Target values      │     │                     │
    │  report-*.md        │     │  (optional)           │     │  Computes:          │
    │       |             │     │                      │     │  - Bayesian update   │
    │       v             │     │  Output:              │     │  - Drift detection  │
    │  VERDICT            │────>│  human-reviews.jsonl  │────>│  - Phase transition │
    │  (GO/COND/NO-GO)    │     │                      │     │                     │
    └─────────────────────┘     └──────────────────────┘     │  Writes:            │
                                                              │  - thresholds.json  │
    ┌─────────────────────┐                                   │  - learning-state   │
    │  PHASE CONTROLLER   │<──────────────────────────────────│    .json            │
    │  (feedback-phase.sh)│                                   └─────────────────────┘
    │                     │
    │  Reads:             │     ┌──────────────────────┐
    │  - learning-state   │     │  THRESHOLD HISTORY   │
    │    .json            │     │  (threshold-         │
    │  - human-reviews    │     │   history.jsonl)     │
    │    .jsonl           │     │                      │
    │                     │     │  Every change logged  │
    │  Decides:           │     │  with:               │
    │  - Review frequency │     │  - before/after      │
    │  - Phase transitions│     │  - trigger reason    │
    │  - Regression alerts│     │  - human review ID   │
    │                     │     │  - confidence level   │
    └─────────────────────┘     └──────────────────────┘

                            DATA FLOW
                            =========

    Pipeline Run ─── results.json ───> Verdict
                                          │
                                          ├── (if review due per Phase Controller)
                                          │         │
                                          │         v
                                          │    Human Review ──> human-reviews.jsonl
                                          │                            │
                                          │                            v
                                          │                    Learning Engine
                                          │                     │         │
                                          │                     v         v
                                          │              thresholds   learning-state
                                          │              .json        .json
                                          │                 │              │
                                          │                 v              v
                                          │           quality-gate.sh   Phase Controller
                                          │           (next run uses     (adjusts review
                                          │            updated           frequency)
                                          │            thresholds)
                                          │
                                          └── (if no review due)
                                                    │
                                                    v
                                              Autonomous proceed
                                              (thresholds unchanged)
```

---

### Data Schema

#### `quality-gate/human-reviews.jsonl`

Each line is one human review:

```json
{
  "id": "review-20260216-150000",
  "timestamp": "2026-02-16T15:00:00+09:00",
  "run_id": "20260216-150000",
  "phase": 1,

  "machine_verdict": "GO",
  "human_verdict": "REJECT",
  "agree": false,

  "reason_category": "too_easy",
  "problematic_metrics": ["damage_taken", "lowest_hp_pct"],
  "target_values": {
    "damage_taken": 5,
    "lowest_hp_pct": 0.85
  },
  "notes": "Bot takes no damage, not engaging at all",

  "metrics_snapshot": {
    "damage_taken": 0,
    "lowest_hp_pct": 1.0,
    "avg_levelup_interval": 6.4,
    "peak_enemies": 8,
    "health_score": 0.45,
    "desire_score": 0.25,
    "dead_time": 7.4,
    "action_density": 1.6,
    "reward_frequency": 27,
    "tier2_score": "3/4"
  }
}
```

#### `quality-gate/learning-state.json`

Persistent state for the learning engine:

```json
{
  "version": 1,
  "last_updated": "2026-02-16T15:00:00+09:00",
  "total_reviews": 5,
  "total_agreements": 3,
  "current_phase": 1,

  "agreement_window": [true, false, true, true, false],
  "agreement_rate": 0.60,

  "threshold_states": {
    "min_damage_taken": {
      "current_value": 2.2,
      "initial_value": 1,
      "observations": 3,
      "confidence": 0.45,
      "delta_accumulator": {
        "running_sum": 4.0,
        "consecutive_same_sign": 2,
        "last_direction": "up",
        "history": [2.0, 2.0]
      },
      "bounds": [0, 20],
      "converged": false
    },
    "min_lowest_hp_pct": {
      "current_value": 0.10,
      "initial_value": 0.10,
      "observations": 0,
      "confidence": 0.0,
      "delta_accumulator": {
        "running_sum": 0,
        "consecutive_same_sign": 0,
        "last_direction": null,
        "history": []
      },
      "bounds": [0.0, 0.5],
      "converged": false
    },
    "min_avg_interval": {
      "current_value": 8.0,
      "initial_value": 8.0,
      "observations": 1,
      "confidence": 0.2,
      "delta_accumulator": {
        "running_sum": -2.0,
        "consecutive_same_sign": 1,
        "last_direction": "down",
        "history": [-2.0]
      },
      "bounds": [3.0, 15.0],
      "converged": false
    }
  },

  "phase_history": [
    {"phase": 1, "entered": "2026-02-16T12:00:00+09:00", "reason": "initial"}
  ],

  "reason_category_counts": {
    "too_easy": 2,
    "too_boring": 1,
    "approve": 3
  }
}
```

#### `quality-gate/threshold-history.jsonl`

Audit log of every threshold change:

```json
{
  "timestamp": "2026-02-16T15:00:05+09:00",
  "trigger": "bayesian_update",
  "review_id": "review-20260216-150000",
  "changes": [
    {
      "threshold": "min_damage_taken",
      "before": 1,
      "after": 2.2,
      "reason": "Human rejected GO with damage_taken=0, target=5. Bayesian EMA alpha=0.33",
      "confidence": 0.45
    }
  ]
}
```

#### Feedback Reason Taxonomy

```json
{
  "categories": {
    "approve": {
      "description": "Machine verdict is correct",
      "threshold_effect": "none (reinforces current values)"
    },
    "too_easy": {
      "description": "Not enough challenge/danger",
      "primary_metrics": ["min_damage_taken", "min_lowest_hp_pct"],
      "direction": "increase difficulty thresholds"
    },
    "too_hard": {
      "description": "Too punishing, unfair deaths",
      "primary_metrics": ["min_lowest_hp_pct", "difficulty_ceiling"],
      "direction": "decrease difficulty thresholds"
    },
    "too_boring": {
      "description": "Nothing happening, dead time",
      "primary_metrics": ["min_peak_enemies", "min_avg_enemies", "max_avg_interval"],
      "direction": "increase density/pacing requirements"
    },
    "too_chaotic": {
      "description": "Too many things on screen, overwhelming",
      "primary_metrics": ["min_peak_enemies"],
      "direction": "cap density requirements"
    },
    "too_fast": {
      "description": "Progression too rapid, no time to appreciate",
      "primary_metrics": ["min_avg_interval", "min_gap_between_levelups"],
      "direction": "increase pacing minimums"
    },
    "too_slow": {
      "description": "Progression too sluggish, waiting for upgrades",
      "primary_metrics": ["max_avg_interval"],
      "direction": "decrease pacing maximums"
    },
    "regression": {
      "description": "Something broke that was working before",
      "primary_metrics": ["warn_threshold_pct", "nogo_threshold_pct"],
      "direction": "tighten regression thresholds"
    },
    "feel_wrong": {
      "description": "Metrics look fine but it does not feel right",
      "primary_metrics": [],
      "direction": "capture in notes for future analysis"
    }
  }
}
```

---

### Integration Points with Existing Pipeline

#### 1. pipeline-orchestrator.sh Integration

After the pipeline produces its verdict, check if a review is due:

```bash
# After existing pipeline output (add to end of pipeline-orchestrator.sh)

# ===== STEP 6: Feedback Loop Check =====
FEEDBACK_DIR="$QG_DIR/feedback"
LEARNING_STATE="$FEEDBACK_DIR/learning-state.json"

if [[ -f "$LEARNING_STATE" ]]; then
    CURRENT_PHASE=$(jq -r '.current_phase' "$LEARNING_STATE")
    TOTAL_RUNS=$(jq '.total_reviews + 1' "$LEARNING_STATE")  # approximate

    REVIEW_DUE=false
    case $CURRENT_PHASE in
        1) REVIEW_DUE=true ;;  # Phase 1: every run
        2) [[ $((TOTAL_RUNS % 3)) -eq 0 ]] && REVIEW_DUE=true ;;
        3) [[ $((TOTAL_RUNS % 10)) -eq 0 ]] && REVIEW_DUE=true ;;
        4) [[ "$QG_VERDICT" == "CONDITIONAL" ]] && REVIEW_DUE=true
           [[ $((TOTAL_RUNS % 20)) -eq 0 ]] && REVIEW_DUE=true ;;
    esac

    if [[ "$REVIEW_DUE" == true ]]; then
        log "[Pipeline] REVIEW DUE (Phase $CURRENT_PHASE)"
        log "[Pipeline] Run: feedback-review.sh $TIMESTAMP"
    fi
fi
```

#### 2. quality-gate.sh Integration

The quality gate reads thresholds from `thresholds.json`. BVAE updates this same file. No changes needed to `quality-gate.sh` -- it automatically uses the updated thresholds on the next run.

The only addition is extending `thresholds.json` with BVAE-managed fields:

```json
{
  "tier1_stability": { /* unchanged */ },
  "tier2_balance": {
    "difficulty_floor": {
      "min_damage_taken": 2.2  // <-- BVAE may update this
    },
    "difficulty_ceiling": {
      "min_lowest_hp_pct": 0.10  // <-- BVAE may update this
    },
    "pacing": {
      "min_avg_interval": 8.0,   // <-- BVAE may update this
      "max_avg_interval": 35.0,  // <-- BVAE may update this
      "min_gap_between_levelups": 2.0
    },
    "density": {
      "min_peak_enemies": 5,     // <-- BVAE may update this
      "min_avg_enemies": 3       // <-- BVAE may update this
    },
    "pass_threshold": 3,
    "nogo_on_ceiling_fail": true
  },
  "tier3_regression": {
    "warn_threshold_pct": 25,
    "nogo_threshold_pct": 50
  },
  "_bvae_managed": true,
  "_bvae_last_update": "2026-02-16T15:00:05+09:00"
}
```

#### 3. gate-log.jsonl Integration

Extend gate log entries with a `human_review_id` field (null if not reviewed):

```json
{
  "timestamp": "2026-02-16T15:00:00+09:00",
  "verdict": "GO",
  "tier2_score": "3/4",
  "damage_taken": 0,
  "lowest_hp_pct": "1",
  "avg_levelup_interval": "6.4",
  "peak_enemies": 8,
  "reasons": "difficulty_floor_warn,pacing_warn",
  "human_review_id": "review-20260216-150000"
}
```

#### 4. Pipeline Report Integration

Add a "Feedback Loop Status" section to the markdown report:

```markdown
## Feedback Loop Status

| Metric | Value |
|--------|-------|
| Phase | 1 (CALIBRATING) |
| Total Reviews | 5 |
| Agreement Rate | 60% (3/5) |
| Review Due | YES |
| Last Threshold Update | 2026-02-16 15:00 |
| Threshold Changes (24h) | 2 |
```

---

### Implementation Plan

#### Phase 1: Data Capture Layer (Day 1)

**Goal**: Create the infrastructure to record human reviews in machine-readable format.

**Files to create**:
- `quality-gate/feedback/feedback-review.sh` -- CLI for human to submit review
- `quality-gate/feedback/human-reviews.jsonl` -- Storage file
- `quality-gate/feedback/reason-taxonomy.json` -- Category definitions

**`feedback-review.sh` specification**:

```bash
#!/usr/bin/env bash
# Feedback Review CLI
# Usage: feedback-review.sh [run_id] [--agree|--reject] [--category CAT] [--metric M=V]
#
# Interactive mode:
#   feedback-review.sh 20260216-150000
#   -> Shows report summary
#   -> Asks: AGREE or REJECT?
#   -> If REJECT: asks category, problematic metrics
#
# Non-interactive (for scripting):
#   feedback-review.sh 20260216-150000 --reject --category too_easy --metric damage_taken=5
#
# Batch mode (review multiple):
#   feedback-review.sh --batch  (reviews all pending)

# Core flow:
# 1. Load results.json and gate-log entry for the given run_id
# 2. Display summary (verdict, key metrics, feel scorecard)
# 3. Prompt: AGREE / REJECT
# 4. If REJECT: prompt category + optional metric targets
# 5. Write to human-reviews.jsonl
# 6. Trigger feedback-learn.sh
```

**Deliverables**:
- Working CLI that captures structured human feedback
- JSONL file accumulating reviews
- Integration hook in pipeline-orchestrator.sh

**Verification**: Run pipeline, submit 3 test reviews, verify JSONL is well-formed.

---

#### Phase 2: Bayesian Learning Engine (Day 2-3)

**Goal**: Implement the learning algorithm that updates thresholds.

**Files to create**:
- `quality-gate/feedback/feedback-learn.sh` -- Learning algorithm
- `quality-gate/feedback/learning-state.json` -- Persistent state
- `quality-gate/feedback/threshold-history.jsonl` -- Audit log

**Algorithm specification**:

```bash
#!/usr/bin/env bash
# Feedback Learning Engine
# Called after each human review. Updates thresholds based on Bayesian EMA.
#
# Algorithm:
# 1. Read latest review from human-reviews.jsonl
# 2. If AGREE: reinforce current thresholds (increase confidence, no value change)
# 3. If REJECT:
#    a. For each problematic metric with a target value:
#       - Compute alpha = 1 / (1 + observations_for_this_metric)
#         (alpha starts at 0.5 for first observation, decreases toward 0)
#       - new_threshold = alpha * target + (1 - alpha) * current
#       - Clamp to safety bounds
#    b. For each problematic metric WITHOUT target value (category-only):
#       - Use category->direction mapping to determine nudge direction
#       - Nudge by 10% of the distance to the safety bound in that direction
#    c. Update delta accumulator (drift detection / F19 safety):
#       - If 3+ consecutive same-direction nudges: apply full step
#       - If alternating: mark as converged, stop adjusting
# 4. Update learning-state.json
# 5. If any threshold changed:
#    - Write new thresholds.json
#    - Append to threshold-history.jsonl
#    - Git commit with message: "bvae: update thresholds from review-XXXX"

# Bayesian EMA update (core math in jq):
# jq --argjson alpha "$ALPHA" --argjson target "$TARGET" \
#   '.tier2_balance.difficulty_floor.min_damage_taken =
#    ($alpha * $target + (1 - $alpha) * .tier2_balance.difficulty_floor.min_damage_taken)' \
#   thresholds.json > thresholds.json.tmp && mv thresholds.json.tmp thresholds.json
```

**Safety mechanisms**:
- All threshold changes are bounded by `[min, max]` ranges
- Changes > 50% of current value require confirmation (logged as "large_shift" warning)
- Rolling back: `git checkout quality-gate/thresholds.json` restores previous state
- Convergence detection: after 3 alternating adjustments, threshold is marked "converged"

**Deliverables**:
- Working learning engine that updates thresholds
- Audit log of all changes
- Safety bounds preventing extreme values

**Verification**: Submit 5 reviews with known biases. Verify thresholds drift in correct direction. Submit 1 outlier review. Verify it does not override the trend.

---

#### Phase 3: Staged Autonomy Controller (Day 4)

**Goal**: Implement the phase system that reduces human review frequency.

**Files to create**:
- `quality-gate/feedback/feedback-phase.sh` -- Phase controller

**Specification**:

```bash
#!/usr/bin/env bash
# Phase Controller
# Called by pipeline-orchestrator.sh to determine if a review is needed.
#
# Reads: learning-state.json
# Writes: learning-state.json (phase transitions)
# Output: "REVIEW_DUE" or "SKIP" to stdout
#
# Phase transitions:
# 1 -> 2: agreement_rate >= 0.80 over last 10 reviews
# 2 -> 3: agreement_rate >= 0.90 over last 15 reviews
# 3 -> 4: agreement_rate >= 0.95 over last 20 reviews
# N -> N-1: agreement_rate < (phase_threshold - 0.10) over last 10 reviews
#
# Review schedule:
# Phase 1: every run
# Phase 2: every 3rd run
# Phase 3: every 10th run
# Phase 4: CONDITIONAL only + every 20th run
```

**Deliverables**:
- Phase controller integrated into pipeline-orchestrator.sh
- Automatic phase transitions with logging
- Regression detection that reverts phases

**Verification**: Simulate 30 reviews with 90% agreement. Verify phase transitions occur at expected points. Inject a streak of disagreements. Verify phase regression.

---

#### Phase 4: Polish and Integration (Day 5)

**Goal**: End-to-end integration, documentation, and first real calibration session.

**Tasks**:
1. Add "Feedback Loop Status" section to pipeline reports
2. Add `--feedback` flag to pipeline-orchestrator.sh for combined run+review
3. Create `feedback-status.sh` -- quick overview of current state
4. Run first real calibration session with gurasu (target: 10 reviews)
5. Verify thresholds are moving in the right direction
6. Commit all feedback data to git

**First calibration session plan**:
1. Run pipeline 10 times (pre-computed, using --skip-run on existing results)
2. Gurasu reviews each: AGREE or REJECT with category
3. Watch thresholds update in real-time
4. After 10 reviews: check agreement rate, verify phase 1 exit is close

---

### Success Metrics

| Metric | Baseline (Day 0) | Target (Day 5) | Target (Day 30) |
|--------|-------------------|-----------------|------------------|
| Human agreement rate | Unknown (no data) | > 60% (after 10 reviews) | > 90% |
| Thresholds updated from feedback | 0 | 3+ thresholds changed | All major thresholds calibrated |
| Human reviews per week | N/A | 10 (calibration phase) | 2-3 (Phase 3) |
| Autonomous phase | N/A | Phase 1 | Phase 3 |
| Time per review | N/A | < 30 seconds | < 15 seconds |
| Threshold drift stability | N/A | Measurable drift | Converged (< 5% change/week) |
| Pipeline health score correlation with human satisfaction | Unknown | r > 0.5 | r > 0.8 |

### Long-Term Vision

Once BVAE is calibrated for Spell Cascade, the learned preferences become transferable to future games in the factory:

1. **Cross-game baselines**: Calibrated thresholds from Spell Cascade become the starting point for the next VS-like game
2. **Genre-specific profiles**: Different threshold profiles for different genres (VS-like, auto-battler, tower defense)
3. **Taste model portability**: The human-reviews.jsonl becomes a "taste dataset" that can inform initial thresholds for any new game without starting calibration from scratch
4. **Meta-learning**: After calibrating 3+ games, patterns emerge (e.g., "gurasu always wants min_damage_taken > 5 regardless of game") that can be hard-coded as factory defaults

---

## Appendix A: Rejected Candidates and Why

| # | Name | Total | Rejection Reason |
|---|------|-------|-----------------|
| F01 | Threshold Auto-Tuning | 16 | Subsumed by F05 (Bayesian is strictly better auto-tuning) |
| F02 | Preference Pair Learning | 13 | High implementation cost; pair selection is complex |
| F03 | Rule Extraction | 13 | Needs 10+ examples before producing output; slow start |
| F04 | Sentiment-Weighted Scoring | 12 | Keyword-to-metric mapping is fragile in bash |
| F06 | Calibration Curve Mapping | 13 | Descriptive only, does not update thresholds directly |
| F07 | Labeling Queue | 15 | Passive; subsumed by F20's Layer 1 |
| F08 | Memory/Context Injection | 13 | Advisory only; similarity metric is hard to define |
| F09 | RLHF-Lite | 10 | Massive overkill; needs Python ML infrastructure |
| F10 | A/B Testing | 14 | Requires running pipeline twice; slow convergence |
| F11 | Verdict Override + Replay | 16 | Good but subsumed by F20; replay is a periodic enhancement |
| F12 | Nelder-Mead | 12 | Requires Python; overkill for 6 parameters |
| F13 | Confidence Bands | 15 | Good concept, folded into learning-state tracking |
| F15 | EMA Consensus | 16 | Subsumed by F05 (Bayesian is EMA with better noise handling) |
| F17 | Grid Search | 14 | Brute force; Bayesian achieves same result more efficiently |

## Appendix B: Feedback Capture Quick Reference

For gurasu's daily use. This is the minimum viable interaction:

```
# After a pipeline run shows a verdict you disagree with:
$ cd /home/namakusa/projects/spell-cascade
$ quality-gate/feedback/feedback-review.sh 20260216-150000 --reject --category too_easy

# After a pipeline run you agree with:
$ quality-gate/feedback/feedback-review.sh 20260216-150000 --agree

# To add specific metric feedback:
$ quality-gate/feedback/feedback-review.sh 20260216-150000 --reject \
    --category too_easy --metric damage_taken=5 --metric lowest_hp_pct=0.85

# To see current system status:
$ quality-gate/feedback/feedback-status.sh

# To see threshold change history:
$ cat quality-gate/feedback/threshold-history.jsonl | jq .
```

The system is designed so that a single `--agree` or `--reject --category X` takes under 10 seconds. Metric-level feedback is optional and provides higher precision but is never required.

## Appendix C: Decision Trace

```
20 candidates generated
  -> Scored on Autonomy Impact, Implementation Effort, Robustness, Data Efficiency (1-5 each)
  -> 2 candidates scored 18 (F05 Bayesian, F20 Composite)
  -> 4 candidates scored 17 (F14, F16, F18, F19)
  -> 3 candidates scored 16 (F01, F11, F15)
  -> Remaining 11 scored 10-15

6 shortlisted: F05, F20, F14, F16, F18, F19
  -> F05 cut from finalist (subsumed by F20 which contains it)
  -> F16 cut from finalist (included as F20's Layer 3)
  -> F18 cut from finalist (taxonomy concept absorbed into F14's interrogation)

3 finalists: F20, F14, F19
  -> F20: Complete system (data + learning + autonomy ramp)
  -> F14: Precision feedback tool (surgical metric updates)
  -> F19: Safety layer (drift detection, oscillation prevention)

THE ONE: BVAE (Bayesian Verdict Alignment Engine)
  -> Synthesis of F20 backbone + F14 interface + F19 safety
  -> Highest leverage: 12 minutes of human time to calibrate system for life
  -> Zero new dependencies: bash + jq + existing thresholds.json
  -> Phased deployment: capture (day 1) -> learn (day 2-3) -> phase (day 4) -> polish (day 5)
  -> Cannot make things worse: safety bounds, drift detection, git-versioned thresholds
```

## Appendix D: Relationship to Existing 20-6-3-1 Documents

| Document | Relationship to BVAE |
|----------|---------------------|
| `game-factory-pipeline-gate-20-6-3-1.md` | BVAE sits ABOVE the pipeline gates. Gates make verdicts; BVAE calibrates the verdicts against human taste |
| `feel-scorecard-20-6-3-1.md` | Feel scorecard metrics (dead time, action density, reward frequency) are inputs to BVAE's metrics snapshot |
| `feel-autoeval-heuristics-20-6-3-1.md` | The "Run Completion Desire" metric is BVAE's primary calibration target (highest weight in health score) |
| `pipeline-baseline-kpi-v1.md` | Baseline KPIs provide the initial "uncalibrated" state. BVAE's job is to move from these values toward human-aligned values |
| `playtest_log.md` | Unstructured human feedback that BVAE replaces with structured, machine-readable feedback |

---

## References

- `quality-gate/thresholds.json` -- Current quality gate thresholds (BVAE's primary output target)
- `quality-gate/quality-gate.sh` -- Existing 3-tier quality gate (reads thresholds.json)
- `quality-gate/gate-log.jsonl` -- Historical machine verdicts (53 entries as of 2026-02-16)
- `tools/pipeline-orchestrator.sh` -- Pipeline orchestrator (integration point for BVAE)
- `playtest_log.md` -- Existing unstructured human feedback
- `pending_for_human.md` -- Phase 1/2/3 autonomy model (BVAE implements this for quality gates)
- `GAME_QUALITY_FRAMEWORK.md` -- Theoretical foundation for quality evaluation
- `docs/feel-scorecard-20-6-3-1.md` -- Feel metrics that feed into BVAE
- `docs/feel-autoeval-heuristics-20-6-3-1.md` -- Heuristics including Run Completion Desire
- `docs/game-factory-pipeline-gate-20-6-3-1.md` -- Pipeline gate system (BVAE calibrates its thresholds)
