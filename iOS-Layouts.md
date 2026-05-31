anchored natural layout with no offsets:

One overlay container.
Header top-aligned with top padding constant.
Recording cluster bottom-aligned with bottom padding constant.
Footer row bottom-aligned with its own bottom padding constant.
No spacer-driven coupling between those three.

Avoid:

Hardcoding padding, use safe-area-aware layout.
Putting critical actions in transient overlays only.
Letting keyboard cover form controls with no scroll or inset behavior.

theme.swift for style tokens
