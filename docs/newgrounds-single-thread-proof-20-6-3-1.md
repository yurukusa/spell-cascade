# Newgrounds Single-Thread Proof (20→6→3→1)
Date: 2026-02-16
Task: explore-spell-cascade-newgrounds-single-thread-proof-20-6-3-1

## Problem Statement

Newgrounds iframe does NOT set `Cross-Origin-Opener-Policy` or `Cross-Origin-Embedder-Policy` headers.
Multi-threaded Godot 4.x builds require `SharedArrayBuffer`, which requires these headers.
Need to prove Spell Cascade's build is single-threaded and compatible.

## 20 Verification Methods (brainstorm)

1. Check `GODOT_THREADS_ENABLED` in SpellCascade.html
2. Check for `.worker.js` file in export
3. Search WASM binary for `nothreads` string
4. Search WASM for `pthread_create` symbols
5. Check `export_presets.cfg` for `variant/thread_support`
6. Check Godot 4.3 default behavior documentation
7. Test with Python HTTP server (no COOP/COEP headers)
8. Test in iframe without special headers
9. Browser console: check `crossOriginIsolated` value
10. Browser console: check `GODOT_THREADS_ENABLED` variable
11. Verify itch.io SharedArrayBuffer checkbox is OFF
12. Compare WASM function names vs multi-threaded reference
13. Check `getMissingFeatures()` logic in SpellCascade.js
14. Search JS for SharedArrayBuffer initialization code
15. Check Emscripten compilation flags in WASM
16. Test on Safari (historically strictest about COOP/COEP)
17. Test on Firefox Android (no SharedArrayBuffer without headers)
18. Check WASM audio worklet function names
19. Compare file set against known multi-threaded export
20. Check Godot export log for thread-related warnings

## Shortlist (6)

### 1. HTML Flag Check (GODOT_THREADS_ENABLED)
Primary, authoritative, 1-second check.

### 2. Worker File Absence
Multi-threaded builds produce `.worker.js`; ours doesn't have one.

### 3. WASM Binary Strings
Contains `nothreads` and `godot_audio_worklet_start_no_threads`. No `pthread_create`.

### 4. Export Preset Default
`variant/thread_support` absent from config = default = false (Godot 4.3).

### 5. JS Feature Check Logic
`getMissingFeatures()` skips SharedArrayBuffer checks when threads disabled.

### 6. itch.io Working Proof
Game already works on itch.io (no COOP/COEP headers = real-world proof).

## Finalists (3)

### A. HTML Flag + Worker Absence (instant, deterministic)
### B. WASM Binary Analysis (deep, irrefutable)
### C. itch.io Working Proof (real-world, pragmatic)

## THE ONE: HTML Flag Check (confirmed single-threaded)

### Evidence (PROOF COMPLETE)

**SpellCascade.html line 103:**
```javascript
const GODOT_THREADS_ENABLED = false;
```

**Supporting evidence (all 5 indicators pass):**

| # | Check | Result | Verdict |
|---|-------|--------|---------|
| 1 | `GODOT_THREADS_ENABLED` in HTML | `false` | SINGLE-THREADED |
| 2 | `.worker.js` file | Absent | SINGLE-THREADED |
| 3 | WASM string `nothreads` | Present | SINGLE-THREADED |
| 4 | WASM string `pthread_create` | Absent | SINGLE-THREADED |
| 5 | `export_presets.cfg` `variant/thread_support` | Absent (default=false) | SINGLE-THREADED |

### Why This Is Definitive

Godot 4.3 defaults to `thread_support=false` for web exports. This was a deliberate change from earlier Godot 4.x which defaulted to threads ON. The HTML flag `GODOT_THREADS_ENABLED = false` is set at export time by the Godot engine and cannot be changed without re-exporting.

### Previous Blocker Status

From `newgrounds-submit-readiness-2026-02-16.md`:
> "Blocker 1: Single-Threaded Export Verification (CRITICAL)"

**STATUS: RESOLVED. Build is single-threaded. No action needed.**

### Newgrounds Compatibility Conclusion

The build:
- Does NOT require `SharedArrayBuffer`
- Does NOT require `crossOriginIsolated`
- Does NOT require COOP/COEP headers
- WILL work in Newgrounds iframe embedding
- Already proven working on itch.io (same header-less environment)

## Files
- HTML file checked: `exports/web/SpellCascade.html`
- Export config: `export_presets.cfg`
- WASM binary: `exports/web/SpellCascade.wasm`
