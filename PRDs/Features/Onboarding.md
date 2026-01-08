# PRD - Onboarding

## Goal
- First launch flow to create 1st project, explain tracking, keep app unblocked.
- Just-in-time permission info when tracking browser domains.

## Scope
- Welcome window (non-blocking) with CTA Create project + Skip.
- Quick project form (name + icon defaults).
- Project detail empty state with CTA Start tracking.
- Permission info modal only when browser domain tracking needs it.
- Tracking active mini card in project detail.

## Non-Goals
- Full tracking logic changes.
- New analytics or logging.
- UI tests.

## User Flows
1) First launch
- Open Welcome window (not fullscreen, not blocking).
- CTA Create project -> Quick create form.
- CTA Skip -> close window, never show again.

2) Create project (onboarding)
- Create project with defaults.
- Close Welcome window.
- Select project in main app.
- Start tracking immediately (manual tracking).

3) Empty project state
- If project has no sessions/summaries and not tracking -> show empty state + Start tracking CTA.

4) Permissions
- Only show info modal when tracking + browser detected + permission not granted.
- Buttons: Open Settings (Privacy > Automation), Later.
- Native macOS permission dialog should still be triggered only when domains need access.

## State + Persistence (UserDefaults)
- Onboarding.hasSeenWelcome (Bool)
- Onboarding.hasCreatedProject (Bool)
- Onboarding.hasAccessibilityPermissionPrompted (Bool)

## Entry / Exit Rules
- Show Welcome if hasSeenWelcome == false.
- Skip sets hasSeenWelcome = true and closes window.
- Create project sets hasCreatedProject = true.
- Permission modal sets hasAccessibilityPermissionPrompted = true.

## UX Notes
- Welcome icon: friendly face.
- Welcome text: 2 lines max, avoid truncation.
- Quick create dialog height compact, no extra whitespace.

## Manual QA
- Fresh app run: Welcome shows once.
- Skip: Welcome never reappears.
- Create project: Welcome closes, project selected.
- Tracking CTA: starts tracking.
- Permission modal: only when browser active + permission missing.

