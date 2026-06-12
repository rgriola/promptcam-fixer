// PromptCam — Compose Script Sheet
// Extracted from CameraView.swift (refactor June 1, 2026)
import SwiftUI

// MARK: - Compose Sheet

/// Modal sheet for editing teleprompter script text.
/// Opens with keyboard focused and provides Save/Cancel toolbar actions.
struct ComposeScriptSheet: View {
    /// Maximum allowed script length (10,000 characters).
    private static let kMaxScriptLength = 10_000
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

    /// Sanitizes script text by trimming whitespace and stripping control characters (except newlines/tabs).
    private func sanitizeScript(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.newlines.union(.init(charactersIn: "\t"))
        let filtered = trimmed.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar) || allowed.contains(scalar)
        }
        return String(String.UnicodeScalarView(filtered))
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
                    .frame(minHeight: 200, maxHeight: .infinity)
                    .onChange(of: draftText) { _, newValue in
                        if newValue.count > Self.kMaxScriptLength {
                            draftText = String(newValue.prefix(Self.kMaxScriptLength))
                        }
                    }

                HStack {
                    Text("Save to apply script updates.")
                        .font(Theme.font12Regular)
                        .foregroundStyle(Theme.primaryText)
                    
                    Spacer()
                    
                    Text("\(draftText.count) / \(Self.kMaxScriptLength)")
                        .font(Theme.font12Regular)
                        .foregroundStyle(draftText.count > Self.kMaxScriptLength ? Theme.red : Theme.primaryText)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.space16)
            .frame(maxHeight: .infinity)
            .navigationTitle("Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark)
            .task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                isEditorFocused = true
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("X", action: onCancel)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let sanitized = sanitizeScript(draftText)
                        let truncated = String(sanitized.prefix(Self.kMaxScriptLength))
                        onSave(truncated)
                    }
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationBackground(Theme.bgGrad)
    }
}
