// PromptCam — recalls priviously saved scripts
import SwiftUI

/// Variant for toolbar placement with text label.
/// Used in navigation bars where system styling is preferred.
struct ArchiveButton: View {
    
    let action: () -> Void
    
    /// Button label text. Defaults to "Save".
    var label: String = "Archive"

    var body: some View {
          Button(action: action) {
              // Image(systemName: "flame.gauge.open")
                Image(systemName: "square.and.arrow.down")
                    .font(Theme.icon16)
                    .foregroundStyle(Theme.white)
          }
          .accessibilityLabel(label)
          .accessibilityHint("Opens saved scripts.")
       
    }
}
