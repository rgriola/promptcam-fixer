// PromptCam — Compose Script Sheet
// Extracted from CameraView.swift (refactor June 1, 2026)
import SwiftUI

// MARK: - Compose Sheet

/// Modal sheet for editing teleprompter script text.
/// Opens with keyboard focused and provides Save/Cancel toolbar actions.
struct ComposeScriptSheet: View {
    /// Maximum allowed script length (10,000 characters).
    private static let kMaxScriptLength = 10_000

    // MARK: - Tuning

    private enum Timing {
        /// Delay before focusing the editor so the fullScreenCover presentation
        /// animation completes before the keyboard slides up. Prevents layout
        /// jump when keyboard appears mid-animation.
        static let focusDelay: Duration = .milliseconds(500)
        /// Delay between dismissing the keyboard and running the callback so
        /// the keyboard animates down before the sheet closes.
        static let keyboardDismissDelay: Duration = .milliseconds(350)
        /// How long the "Cleaned" confirmation stays visible on the Clean button.
        static let cleanIndicatorDuration: Duration = .milliseconds(1500)
    }

    private enum Layout {
        /// Editor height as a fraction of available height.
        static let editorHeightRatio: CGFloat = 0.45
    }

    /// Local draft text edited before save is committed.
    @State private var draftText: String
    /// Focus binding used to open the keyboard on sheet presentation.
    @FocusState private var isEditorFocused: Bool
    /// Controls visibility of the script archive sheet.
    @State private var showArchive = false
    /// Tracks whether the clean action just ran — shows a brief "Cleaned" confirmation.
    @State private var didClean = false
    /// Cancellable Task that resets `didClean` after the indicator duration.
    @State private var cleanIndicatorTask: Task<Void, Never>?
    /// Cancellable Task that runs a dismiss callback after the keyboard
    /// animates down. Cancelled on view disappear.
    @State private var dismissTask: Task<Void, Never>?
    /// Callback fired with latest text when user saves.
    let onSave: (String) -> Void
    /// Callback fired when user cancels editing.
    let onCancel: () -> Void

    /// Creates compose sheet state from current teleprompter text.
    /// Truncates `initialText` to the maximum allowed length so the character
    /// count never opens in an over-limit state.
    /// - Parameters:
    ///   - initialText: Source text shown when compose opens.
    ///   - onSave: Callback invoked with user-edited script.
    ///   - onCancel: Callback invoked when user dismisses without saving.
    init(initialText: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        let clamped = String(initialText.prefix(Self.kMaxScriptLength))
        _draftText = State(initialValue: clamped)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    /// True when the draft has any non-whitespace content.
    private var hasContent: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    /// Removes paste-in formatting artifacts from apps like Outlook, Word, and Slack
    /// so the script is ready for teleprompter use.
    ///
    /// Steps applied in order:
    /// 1. Normalize line endings (\r\n → \n)
    /// 2. Replace non-breaking spaces with regular spaces
    /// 3. Strip ==OC== markers (case-insensitive)
    /// 4. Per line: remove leading whitespace, trailing whitespace, and common bullet prefixes
    /// 5. Collapse runs of more than one blank line into a single blank line
    /// 6. Trim leading and trailing blank lines
    private func cleanForTeleprompter(_ text: String) -> String {
        // Early return — no work to do on empty input.
        guard !text.isEmpty else { return text }

        // 1. Normalize line endings.
        var result = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r",   with: "\n")

        // 2. Non-breaking spaces → regular space.
        result = result.replacingOccurrences(of: "\u{00A0}", with: " ")

        // 3. Strip ==OC== markers.
        result = result.replacingOccurrences(of: "==OC==", with: "",
                                             options: [.caseInsensitive])

        // 4. Per-line cleanup — uses CharacterSet.whitespaces to catch the full
        //    Unicode whitespace set: \t, space, non-breaking space, en-space,
        //    em-space, figure space, and other variants Outlook/Word insert.
        let wsSet = CharacterSet.whitespaces   // does NOT include newlines
        let bulletPrefixes = ["\u{2022} ", "\u{00B7} ", "\u{25CF} ", "\u{25E6} ",
                              "- ", "* ", "\u{2013} ", "\u{2014} "]

        func stripLeading(_ s: String) -> String {
            String(s.unicodeScalars.drop(while: { wsSet.contains($0) }))
        }
        func stripTrailing(_ s: String) -> String {
            var scalars = s.unicodeScalars
            while let last = scalars.last, wsSet.contains(last) { scalars.removeLast() }
            return String(scalars)
        }

        let cleaned: [String] = result
            .components(separatedBy: "\n")
            .map { line in
                var l = stripLeading(line)
                l = stripTrailing(l)
                // Remove leading bullet / list prefix, then strip again in case
                // extra whitespace follows the bullet character.
                for prefix in bulletPrefixes where l.hasPrefix(prefix) {
                    l = stripLeading(String(l.dropFirst(prefix.count)))
                    break
                }
                return l
            }

        // 5. Collapse multiple consecutive blank lines to at most one.
        var output: [String] = []
        var blankRun = 0
        for line in cleaned {
            if line.isEmpty {
                blankRun += 1
                if blankRun == 1 { output.append(line) }
            } else {
                blankRun = 0
                output.append(line)
            }
        }

        // 6. Trim leading / trailing blank lines.
        return output.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Dismisses the keyboard and waits for it to animate down before
    /// running the callback. Prevents the camera preview from being visible
    /// in a "narrowed" state when the fullScreenCover closes.
    /// Uses a cancellable Task so an in-flight dismiss is cancelled if the
    /// view disappears (e.g. system dismiss during the delay window).
    private func dismissAndRun(_ action: @escaping () -> Void) {
        dismissTask?.cancel()
        isEditorFocused = false
        dismissTask = Task {
            try? await Task.sleep(for: Timing.keyboardDismissDelay)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    /// Script editor UI with immediate keyboard focus.
    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let editorHeight = geo.size.height * Layout.editorHeightRatio

                VStack(spacing: Theme.space12) {
                    // Info bar above editor
                    HStack {
                        Text("\(draftText.count) / \(Self.kMaxScriptLength)")
                            .font(Theme.font12Regular)
                            .foregroundStyle(draftText.count > Self.kMaxScriptLength ? Theme.red : Theme.primaryText)
                            .monospacedDigit()

                            Spacer()

                        Text("Save to apply script updates.")
                            .font(Theme.font12Regular)
                            .foregroundStyle(Theme.primaryText)
                        
                    
                    }

                    // Text editor
                    TextEditor(text: $draftText)
                        .font(Theme.font16Regular)
                        .focused($isEditorFocused)
                        .padding(Theme.space4)
                        .background(
                            Theme.panelBg.opacity(0.2), 
                            in: RoundedRectangle(cornerRadius: Theme.radiusMd))
                        .frame(height: editorHeight)
                        .onChange(of: draftText) { _, newValue in
                            if newValue.count > Self.kMaxScriptLength {
                                draftText = String(newValue.prefix(Self.kMaxScriptLength))
                            }
                        }

                    // Action buttons row: Clean (left) | Clear (right)
                    HStack {
                        // Clean for Teleprompter — strips paste-in formatting artifacts.
                        Button {
                            draftText = cleanForTeleprompter(draftText)
                            didClean = true
                            cleanIndicatorTask?.cancel()
                            cleanIndicatorTask = Task {
                                try? await Task.sleep(for: Timing.cleanIndicatorDuration)
                                guard !Task.isCancelled else { return }
                                didClean = false
                            }
                        } label: {
                            Label(
                                didClean ? "Cleaned" : "Clean for Teleprompter",
                                systemImage: didClean ? "checkmark.circle.fill" : "wand.and.sparkles"
                            )
                            .font(Theme.font16Regular)
                            .foregroundStyle(didClean ? Theme.green : Theme.white)
                            .animation(.easeInOut(duration: 0.2), value: didClean)
                        }
                        .opacity(hasContent ? 1.0 : 0.3)
                        .disabled(!hasContent)
                        .accessibilityLabel("Clean script formatting")
                        .accessibilityHint("Removes indents, bullets, and paste artifacts from Outlook or Word")

                        Spacer()

                        // Clear — wipes the editor entirely.
                        Button {
                            draftText = ""
                        } label: {
                            Label("Clear", systemImage: "xmark.circle.fill")
                                .font(Theme.font16Regular)
                                .foregroundStyle(Theme.white)
                        }
                        .opacity(hasContent ? 1.0 : 0.3)
                        .disabled(!hasContent)
                    }

                    Spacer()
                }
                .padding(Theme.space16)

            }
            .ignoresSafeArea(.keyboard)
            .navigationTitle("Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark)
            .task {
                // Delay keyboard focus until the fullScreenCover presentation
                // animation completes. Without this, keyboard slides up while
                // the sheet is still animating in — causes visible layout jump.
                try? await Task.sleep(for: Timing.focusDelay)
                guard !Task.isCancelled else { return }
                isEditorFocused = true
            }
            .onDisappear {
                cleanIndicatorTask?.cancel()
                dismissTask?.cancel()
            }

            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CloseToolbarButton { dismissAndRun { onCancel() } }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: Theme.space16) {
                        Button {
                            showArchive = true
                        } label: {
                            Image(systemName: "flame.gauge.open")
                        }
                        .accessibilityLabel("Recent scripts")
                        .accessibilityHint("Restore a previously saved script")

                        SaveToolbarButton(
                            action: {
                                let sanitized = sanitizeScript(draftText)
                                let truncated = String(sanitized.prefix(Self.kMaxScriptLength))
                                ScriptArchive.save(truncated)
                                dismissAndRun { onSave(truncated) }
                            },
                            isDisabled: !hasContent
                        )
                    }
                }
            }
        }
        .presentationBackground(Theme.bgGrad)
        .sheet(isPresented: $showArchive) {
            ScriptArchiveSheet { restoredText in
                draftText = restoredText
            }
        }
    }
}
