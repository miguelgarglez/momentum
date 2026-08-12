# Momentum — Focus Session v0 (Rewrite)

**Status:** active rewrite  
**Branch:** `rewrite/focus-v0`  
**Branding:** Momentum (same name/icon family; no mascot)  
**Legacy:** v1 auto-tracker remains on `main` / git history

---

## 1. One-liner

Momentum is a native macOS menu-bar app for **intentional focus sessions** on personal projects — local-first, trustworthy numbers, zero guessing. It should feel like a **solid clock**: always correct, low friction, invisible until you need it.

## 2. Problem

Side projects need visible progress. Auto-tracking apps/domains feels magical until it lies (wrong project, missing browser, permission friction). Trust breaks; the habit dies.

## 3. Solution (v0)

Manual focus sessions only (open chronometer, not pomodoro):

1. Start focus on a project from the menu bar (or global hotkey on last project)
2. Work — menu bar shows **live elapsed** + project identity
3. Stop (optional short note: what you did)
4. See today / this week per project

Every minute exists because the user asked for it.

## 4. Target user (narrow)

You (builder with side projects on a Mac) who wants an honest log of deep work — not RescueTime, not a pet coach.

## 5. Core loop

| Step | Behavior |
|------|----------|
| Start | Menu bar → last project / pick project → chronometer runs; clear “in focus” state |
| During | Status item shows live `MM:SS` or `H:MM:SS`; optional idle pause via IOKit `HIDIdleTime` |
| Stop | Persist session (start, end, paused duration, project, optional ≤80 char note) |
| Review | Menu + main window: today and last 7 days totals; project detail = recent sessions |

## 6. Decisions locked

| Topic | Choice |
|-------|--------|
| Timer model | Open chronometer (count up) |
| Menu bar while focusing | Live elapsed + project cue |
| Menu bar idle | Quiet icon; today summary in menu |
| UI language | Spanish only in v0 |
| Reliability bar | Single source of truth, explicit state machine, idempotent start/stop, recover open sessions on launch |

## 7. In scope (v0)

- Projects: name + color  
- Start / stop (+ global hotkey toggle for last project)  
- SwiftData: `Project`, `FocusSession` (manual only; `endAt == nil` = open)  
- Menu-bar-first; Dock only when a window is visible  
- Today + 7-day totals  
- Optional note on stop  
- Optional idle pause  
- Crash / quit: close open session safely (`wasInterrupted`)  
- Spanish UI copy (hardcoded; no dual i18n yet)

## 8. Explicitly out of scope (v0)

- App / domain / file auto-tracking  
- AppleScript, Automation TCC, conflict rules, pending time  
- Raycast / local HTTP API  
- Heatmaps, streaks, achievements, onboarding theater  
- iCloud, CSV export, “DB encryption” claims  
- Mascot  

**Landing** lives in-repo later (`landing/`); not a blocker for app v0.  
**Raycast** = phase 2 only if the 14-day habit sticks.

## 9. Reliability principles (“reloj de bien”)

1. One source of truth for in-progress time (session controller; UI observes).  
2. Explicit phases: `Idle` → `Running` ↔ `PausedIdle` → `Idle`.  
3. Idempotent stop; start while running = stop previous then start (atomic).  
4. Persist before clearing UI; quit closes the open session.  
5. No fragile TCC (no Automation / Accessibility required).  
6. Menu bar is the product; the window is for review/management.

## 10. Success criteria (maker)

In 14 calendar days after a usable build:

- ≥10 days with ≥1 real session  
- Menu-bar time matches session history (no distrust)  
- Zero visits to Automation / Accessibility panes for this app  

If start/stop doesn’t stick → pivot or pause; do not add features.

## 11. Phase 2 (only after success)

- Suggest last foreground app’s usual project (`NSWorkspace` only) — suggest ≠ assign  
- Raycast: start / stop / today  
- Landing page in monorepo  
- EN+ES if needed  
- Notarization / Sparkle when distributing beyond self

## 12. Engineering constraints

- New app surface on this branch (replace v1 code paths; do not revive `ActivityTracker`)  
- Layers: Views → Services → Models → Utilities  
- Reuse patterns only: status item lifecycle, Dock visibility, Makefile/CI basics, visual branding  
- Keep the app boringly correct before it is interesting

## 13. Mantra (unchanged spirit)

Measure progress, not productivity. Local by default. No judgment.  
**Updated promise:** mark your focus; see project progress — without guessing which app you were.
