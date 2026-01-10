# Views Guidelines

## Scope
- This folder holds SwiftUI views organized by feature or shared UI.
- Keep views small, composable, and focused on presentation.
- Prefer extracting subviews into feature folders rather than adding large view bodies.
 - Example entries: `ProjectDetailView`, `ProjectFormView`, `WeeklySummaryChartView`, `PendingConflictResolutionView`.

## Conventions
- File name matches the primary view type.
- Avoid feature-specific logic in `Views/Components/` and `Views/Styles/`.
- Use `LTRTextField` + `macRoundedTextFieldStyle()` for macOS editable fields.
- Reuse shared styles via `DetailCardStyles` instead of duplicating modifiers.
- Tracker settings exclusions should cover apps, domains, and file patterns (exact paths or suffixes) with concise helper text.
- Automation permission guidance should reuse `AutomationPermissionPromptView` (e.g., from Settings) for consistent user education.

## Layout
- `Views/Dashboard/`: dashboard header/metrics and related UI.
- `Views/Projects/`: project detail, charts, forms, list views.
- `Views/Settings/`: app and tracking settings views.
- `Views/Tracking/`: conflict resolution and tracking-specific UI.
- `Views/Components/`: reusable UI building blocks.
- `Views/Styles/`: shared view modifiers/styles.
