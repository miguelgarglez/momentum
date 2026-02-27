# Store Metadata Draft (Submission Prep)

## Short Description

Control the Momentum macOS app from Raycast: open app/settings, list projects, resolve conflicts, and manage manual tracking.

## Long Description

Momentum for Raycast connects to the local Momentum macOS companion app to speed up project and tracking workflows.

Use it to:
- Open Momentum quickly.
- Jump into Momentum settings for Raycast integration.
- Browse and open projects.
- Start and stop manual tracking sessions.
- Open pending conflict resolution when needed.

The extension communicates locally with Momentum on loopback and requires Momentum to be installed, running, and paired.

## Reviewer Notes

- Companion app dependency: Momentum (macOS).
- Setup requirement: Pair via 4-digit code in `Momentum > Settings > Raycast Extension`.
- If Momentum is missing or integration is unavailable, commands provide explicit error guidance.
- Platform scope intentionally limited to macOS.

## Pre-Submission Command

```bash
cd RaycastExtension/momentum
npm run publish
```

Do not run this until checklist in `RELEASE_CHECKLIST.md` is complete.
