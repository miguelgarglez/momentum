# Utilities Guidelines

## Scope
- Reusable helpers, formatters, extensions, and small utility types.
- Keep utilities generic and free of feature‑specific assumptions.
- Examples in this folder: `Color+Hex`, `HeatmapIntensityCalculator`, `TimeFormatting`.

## Conventions
- Prefer focused extensions over large grab‑bag files.
- Keep naming explicit about units and formatting rules.
- Avoid side effects; utilities should be deterministic.
 - When reading system resources (e.g. symbol catalogs), provide a fallback list for resilience.
