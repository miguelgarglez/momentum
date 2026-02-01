# Components Guidelines

## Scope
- Reusable UI blocks with minimal dependencies.
- Components should be portable across features.
 - Examples in this folder: `ActionPanelView`, `ToastView`, `FlowLayout`, `LTRTextField`, `SFSymbolPickerView`, `SystemEmojiPickerButton`, `ProjectIconGlyph`.

## Conventions
- Keep APIs simple and explicit (inputs + callbacks).
- Avoid feature-specific styling or model assumptions.
- Use `AnyView` only when necessary to erase type differences.
- Provide accessibility labels where user interaction is present.
- For window-level behavior, emit notifications and let coordinators decide global app state.
- AppKit window mutations (e.g., `NSWindow.delegate`) require `@MainActor`; use `@MainActor`/`Task { @MainActor in ... }` for delegate updates.
 - For hidden text fields that interact with system panels, keep them co-located with the triggering control so the OS anchor feels aligned.

## Layout
- Prefer small subcomponents if a component grows beyond ~150 lines.
