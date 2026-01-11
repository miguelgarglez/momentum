# Components Guidelines

## Scope
- Reusable UI blocks with minimal dependencies.
- Components should be portable across features.
 - Examples in this folder: `ActionPanelView`, `ToastView`, `FlowLayout`, `LTRTextField`.

## Conventions
- Keep APIs simple and explicit (inputs + callbacks).
- Avoid feature-specific styling or model assumptions.
- Use `AnyView` only when necessary to erase type differences.
- Provide accessibility labels where user interaction is present.
- For window-level behavior, emit notifications and let coordinators decide global app state.

## Layout
- Prefer small subcomponents if a component grows beyond ~150 lines.
