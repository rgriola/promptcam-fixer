// June 4, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Extracted from TeleprompterOverlayView (Phase 4)
import UIKit

/// Pure UIKit text-height measurement for teleprompter layout.
/// Uses the same horizontal padding and font as ScrollingTeleprompterText so
/// geometry calculations stay accurate.
/// - Returns: Total height (text + vertical padding), or `nil` if `viewWidth` is zero.
func measureTeleprompterTextHeight(text: String, fontSize: Double, viewWidth: CGFloat) -> CGFloat? {
    guard viewWidth > 0 else { return nil }
    let availableWidth = max(viewWidth - Theme.teleprompterHPad * 2, 1)
    let uiFont = UIFont.systemFont(ofSize: CGFloat(fontSize), weight: .semibold)
    let attributes: [NSAttributedString.Key: Any] = [.font: uiFont]
    let bounding = (text as NSString).boundingRect(
        with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: attributes,
        context: nil
    )
    return ceil(bounding.height) + Theme.space16 * 2
}

/// Composite key used by `.task(id:)` to trigger re-measurement when the text,
/// font size, or available width changes. Uses text length + a hash so giant
/// strings don't get fully copied on every body eval.
struct TextMeasureKey: Hashable {
    let length: Int
    let hash: Int
    let fontSize: Double
    let width: CGFloat

    init(text: String, fontSize: Double, width: CGFloat) {
        self.length = text.count
        self.hash = text.hashValue
        self.fontSize = fontSize
        self.width = width
    }
}
