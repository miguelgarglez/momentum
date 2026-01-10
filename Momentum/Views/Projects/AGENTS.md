# Projects Views Guidelines

## Scope
- Project-centric UI: detail screens, activity charts, forms, list cells, and helpers.
- Keep business logic in models/services; views should format and present.
- Examples in this folder: `ProjectDetailView`, `ProjectWeeklySummaryChartView`, `ProjectActivityHistoryViews`, `ProjectFormView`, `ProjectListViews`.

## Conventions
- Favor small subviews for sections (cards, rows, headers).
- Keep `ProjectDetailView` focused on composition; move heavy UI blocks into sibling views.
- Keep form state in `ProjectFormDraft` and pass bindings into view sections.
- Prefer `detailCardStyle` and related shared styles for cards.

## Data and State
- Avoid duplicating derived data; compute in view-only helpers where needed.
- Use `@State` for purely local UI state (selection, hover, expanded/collapsed).
- When introducing new sections, provide a preview-only data path where possible.
