// PromptCam — Compose Script Sheet
// Extracted from CameraView.swift (refactor June 1, 2026)
import SwiftUI

// MARK: - Compose Sheet

/// Modal sheet for editing teleprompter script text.
/// Opens with keyboard focused and provides Save/Cancel toolbar actions.
struct ComposeScriptSheet: View {
    /// Local draft text edited before save is committed.
    @State private var draftText: String
    /// Focus binding used to open the keyboard on sheet presentation.
    @FocusState private var isEditorFocused: Bool
    /// Callback fired with latest text when user saves.
    let onSave: (String) -> Void
    /// Callback fired when user cancels editing.
    let onCancel: () -> Void

    /// Creates compose sheet state from current teleprompter text.
    /// - Parameters:
    ///   - initialText: Source text shown when compose opens.
    ///   - onSave: Callback invoked with user-edited script.
    ///   - onCancel: Callback invoked when user dismisses without saving.
    init(initialText: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _draftText = State(initialValue: initialText)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    /// Script editor UI with immediate keyboard focus.
    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.space12) {
                TextEditor(text: $draftText)
                    .font(Theme.font16Regular)
                    .focused($isEditorFocused)
                    .padding(Theme.space8)
                    .background(Theme.panelBg.opacity(0.2), in: RoundedRectangle(cornerRadius: Theme.radiusMd))

                Text("Edits are applied to the teleprompter text when you tap Save.")
                    .font(Theme.font12Regular)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Theme.space16)
            .navigationTitle("Compose")
            .onAppear {
                DispatchQueue.main.async {
                    isEditorFocused = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(draftText)
                    }
                }
            }
        }
    }
}
