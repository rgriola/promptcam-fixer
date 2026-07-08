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

Icon Defines the background.
Making the circle scale with the icon
The cleanest SwiftUI pattern is to let the icon define the size, then use .background with a Circle behind it — instead of the current ZStack where the Circle fills whatever frame the parent hands it (currently a fixed .frame(width: 40, height: 40) from the parent).

ways to stack icons

Zstack
ZStack {
Image(systemName: "square.fill")
.font(.system(size: 40))
.foregroundStyle(.blue)

    Image(systemName: "chevron.right")
        .font(.system(size: 20))
        .foregroundStyle(.white)
        .offset(x: 2)  // Fine-tune position

}

badges

Image(systemName: "square.fill")
.font(.system(size: 40))
.foregroundStyle(.blue)
.overlay(
Image(systemName: "chevron.right")
.font(.system(size: 20))
.foregroundStyle(.white)
.offset(x: 2)
)

for underlays
Image(systemName: "chevron.right")
.font(.system(size: 20))
.foregroundStyle(.white)
.background(
Image(systemName: "circle.fill")
.font(.system(size: 40))
.foregroundStyle(.blue)
)
