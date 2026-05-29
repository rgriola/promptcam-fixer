May 29, 2026 - 12:57pm - GitHub Copilot

# PromptCam iOS Design System — Styling Guide

> This is the PromptCam-specific styling guide.
> All SwiftUI views must use Theme tokens only.
> All font sizes must be even numbers.

---

## 1. Architecture: `Theme.swift`

All styling lives in a single file: **`App/Theme.swift`** — an `enum Theme` with no cases (namespace only). No styling should be defined inline in views.

### Rules

| ✅ Do                                                        | ❌ Don't                                         |
| ------------------------------------------------------------ | ------------------------------------------------ |
| `.font(Theme.font16Medium)`                                  | `.font(.system(size: 16, weight: .medium))`      |
| `.foregroundStyle(Theme.white)`                              | `.foregroundStyle(.white)`                       |
| `.clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))` | `.clipShape(RoundedRectangle(cornerRadius: 12))` |
| `.padding(.horizontal, Theme.space16)`                       | `.padding(.horizontal, 16)`                      |
| `.background(Theme.glassOverlay)`                            | `.background(Color.white.opacity(0.05))`         |

---

## 2. FontFamily Lever

A single line controls the entire app's typeface:

```swift
enum FontFamily {
    case system                // SF Pro (default)
    case custom(String)        // e.g. "Inter", "Outfit"

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .system:       return .system(size: size, weight: weight)
        case .custom(let n): return .custom(n, size: size)
        }
    }

    func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

enum Theme {
    static let fontFamily: FontFamily = .system   // ← change here to restyle everything
}
```

To swap to a custom font, bundle the font files, register in `Info.plist`, then change:

```swift
static let fontFamily: FontFamily = .custom("Inter")
```

---

## 3. Typography — 5-Size Scale (Even Sizes Only)

Every text element maps to one of **5 even point sizes**. No exceptions.

| Tier   | Size | Use Cases                                                         |
| ------ | ---- | ----------------------------------------------------------------- |
| **xs** | 10pt | Timestamps, helper text, status dots                              |
| **sm** | 12pt | Captions, metadata labels, badges, error text                     |
| **md** | 16pt | Body text, buttons, nav titles, input fields                      |
| **lg** | 20pt | Section titles, screen headers                                    |
| **xl** | 28pt | Hero/login headings, large initials                               |

### Naming Convention

All font tokens follow the pattern: **`font{size}{Weight}`**

```swift
// xs — 10pt
static let font10Regular   = fontFamily.font(size: 10)
static let font10Medium    = fontFamily.font(size: 10, weight: .medium)
static let font10Semibold  = fontFamily.font(size: 10, weight: .semibold)

// sm — 12pt
static let font12Regular   = fontFamily.font(size: 12)
static let font12Medium    = fontFamily.font(size: 12, weight: .medium)
static let font12Semibold  = fontFamily.font(size: 12, weight: .semibold)

// md — 16pt
static let font16Regular   = fontFamily.font(size: 16)
static let font16Medium    = fontFamily.font(size: 16, weight: .medium)
static let font16Semibold  = fontFamily.font(size: 16, weight: .semibold)
static let font16Bold      = fontFamily.font(size: 16, weight: .bold)

// lg — 20pt
static let font20Semibold  = fontFamily.font(size: 20, weight: .semibold)
static let font20Bold      = fontFamily.font(size: 20, weight: .bold)

// xl — 28pt
static let font28Light     = fontFamily.font(size: 28, weight: .light)
static let font28Bold      = fontFamily.font(size: 28, weight: .bold)
```

> **Adding a weight:** If you need `font12Bold`, add it to Theme.swift and use it everywhere — never inline.

---

## 4. Monospaced Fonts

For IDs, codes, timecodes, and technical values. Always uses system monospaced regardless of FontFamily.

Pattern: **`mono{size}{Weight}`**

```swift
static let mono10Medium = fontFamily.mono(size: 10, weight: .medium)
static let mono12Medium = fontFamily.mono(size: 12, weight: .medium)
static let mono16Medium = fontFamily.mono(size: 16, weight: .medium)
static let mono16Bold   = fontFamily.mono(size: 16, weight: .bold)
```

Special case for animated counters:

```swift
static let progressFont = Font.caption.monospacedDigit()
```

---

## 5. Icons

SF Symbols are sized by font. Icon tokens mirror the text scale.

Pattern: **`icon{size}`**

```swift
static let icon12 = fontFamily.font(size: 12)   // inline status indicators
static let icon16 = fontFamily.font(size: 16)   // standard inline icons
static let icon20 = fontFamily.font(size: 20)   // header action icons
```

Usage:

```swift
Image(systemName: "arrow.clockwise")
    .font(Theme.icon20)
    .foregroundStyle(Theme.blue)
```

---

## 6. Display Tier

For emoji, hero graphics, and decorative elements that sit **outside** the type scale.

Pattern: **`display{size}`**

```swift
static let display24 = fontFamily.font(size: 24)
static let display32 = fontFamily.font(size: 32)
static let display44 = fontFamily.font(size: 44, weight: .bold)   // play/pause overlays
static let display64 = fontFamily.font(size: 64)                  // empty state emoji
```

---

## 7. Color Architecture (PromptCam Palette)

### Core Palette (never use bare system colors)

```swift
static let black   = Color(hex: "#0B0B0B")    // NOT Color.black
static let white   = Color(hex: "#F7F7F7")    // NOT Color.white / .white
static let blue    = Color(hex: "#1E7AF0")
static let green   = Color(hex: "#30D158")
static let red     = Color(hex: "#FF3B30")
static let yellow  = Color(hex: "#FFD60A")
static let gray    = Color(hex: "#8E8E93")
```

### Semantic Colors

```swift
// Backgrounds
static let cameraBg    = Color(hex: "#0B0B0B")
static let panelBg     = Color(hex: "#1C1C1E")
static let separator   = Color(hex: "#2C2C2E")
static let overlayScrim = Color(hex: "#000000")

// Text hierarchy
static let primaryText   = Color(hex: "#F7F7F7")
static let secondaryText = Color(hex: "#A1A1A6")
static let tertiaryText  = Color(hex: "#6E6E73")

// Glass effects
static let glassOverlay = Color.white.opacity(0.08)
static let glassBorder  = Color.white.opacity(0.12)
```

### Enforcement Rules

- **No bare system colors:** `.white`, `.red`, `.blue`, `Color.black` → always `Theme.white`, `Theme.red` etc.
- **No `Color(hex:)` in views:** All hex values live in Theme.swift only.
- **Opacity is OK inline:** `Theme.white.opacity(0.6)` is fine — the base color is still a Theme token.

---

## 8. Corner Radii — 4 Tokens

```swift
static let radiusSm: CGFloat = 8     // thumbnails, small chips
static let radiusMd: CGFloat = 12    // cards, inputs, buttons
static let radiusLg: CGFloat = 16    // sheets, modals, large cards
static let radiusXl: CGFloat = 20    // hero elements, bubble containers
```

**Rule:** Never write a raw `cornerRadius` number in a view. Always use `Theme.radius*`.

---

## 9. Spacing — 8px Grid

```swift
static let space4:  CGFloat = 4
static let space8:  CGFloat = 8
static let space12: CGFloat = 12
static let space16: CGFloat = 16
static let space20: CGFloat = 20
static let space24: CGFloat = 24
static let space32: CGFloat = 32
```

**When to use tokens vs. raw values:** Use tokens for repeated horizontal/vertical padding. Raw values are OK for one-off layout tweaks (e.g., `.padding(.top, 50)` for toolbar inset).

---

## 10. Composite Constants

Repeated patterns get promoted to static constants:

```swift
// Gradients
// Button layout
static let buttonPaddingH:    CGFloat = 14
static let buttonPaddingV:    CGFloat = 8
static let buttonCornerRadius: CGFloat = radiusMd
```

**Rule:** If you see the same gradient, padding combo, or background pattern used 3+ times, extract it to Theme.swift.

---

## 11. Quick Reference: Choosing a Token

| I need to style...         | Token to use                                  |
| -------------------------- | --------------------------------------------- |
| Body text in a chat bubble | `Theme.font16Regular`                         |
| A small gray timestamp     | `Theme.font10Regular` + `Theme.secondaryText` |
| A section title            | `Theme.font20Bold` + `Theme.white`            |
| A button label             | `Theme.font16Semibold` + `Theme.white`        |
| An error message           | `Theme.font12Regular` + `Theme.red`           |
| A metadata ID              | `Theme.mono12Medium` + `Theme.secondaryText`  |
| An SF Symbol in a button   | `Theme.icon16`                                |
| A header refresh icon      | `Theme.icon20` + `Theme.blue`                 |
| A large empty-state emoji  | `Theme.display64`                             |
| A card background          | `Theme.panelBg` with `Theme.radiusMd`         |
| A glass overlay panel      | `Theme.glassOverlay` with `Theme.glassBorder` |

---

## 12. Hex Color Extension

Include this in Theme.swift to support `Color(hex:)`:

```swift
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
```

---

## 13. Checklist for New Views

Before merging any new SwiftUI view, verify:

- [ ] **Zero** `.font(.system(size:))` calls — all fonts use `Theme.font*`
- [ ] **Zero** bare system colors (`.white`, `.red`, `Color.black`) — all use `Theme.*`
- [ ] **Zero** raw `cornerRadius` numbers — all use `Theme.radius*`
- [ ] **Zero** inline gradients — reuse `Theme.*Gradient` or add a new one
- [ ] Icons use `Theme.icon*` sizing, not inline `.font(.system(size:))`
- [ ] Repeated padding values use `Theme.space*` tokens
