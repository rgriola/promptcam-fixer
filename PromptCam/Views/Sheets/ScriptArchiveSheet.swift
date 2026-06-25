import SwiftUI

/// Sheet displaying recent script versions for quick restore.
struct ScriptArchiveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scripts: [ArchivedScript] = []
    /// Callback fired with the selected script text.
    let onRestore: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack {
                if scripts.isEmpty {
                    ContentUnavailableView(
                        "No Recent Scripts",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Saved scripts appear here for 7 days.")
                    )
                    .foregroundStyle(Theme.white)
                } else {
                    List {
                        ForEach(scripts) { script in
                            Button {
                                onRestore(script.text)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(script.preview)
                                        .font(Theme.font12Regular)
                                        .foregroundStyle(Theme.primaryText)
                                        .lineLimit(2)

                                    Text(script.relativeTimestamp)
                                        .font(Theme.font12Regular)
                                        .foregroundStyle(Theme.primaryText)
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Theme.panelBg.opacity(0.2))
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                ScriptArchive.delete(id: scripts[index].id)
                            }
                            scripts.remove(atOffsets: indexSet)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Recent Scripts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CloseToolbarButton { dismiss() }
                }
            }
        }
        .presentationBackground(Theme.bgGrad)
        .presentationDetents([.medium])
        .onAppear {
            scripts = ScriptArchive.load()
        }
    }
}
