import SwiftUI

// Church Notes Command Bar — triggered by / in the composer.
// All AI results are editable before insertion; nothing auto-saves.
// Liquid Glass used for the floating command tray only.
struct ChurchNotesCommandBarView: View {

    @ObservedObject var viewModel: ChurchNotesContextViewModel
    let noteText: String
    @State private var query: String = ""
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isQueryFocused: Bool

    private var filteredCommands: [CNCommandBarCommand] {
        let q = query.lowercased()
        guard !q.isEmpty else { return CNCommandBarCommand.allCases }
        return CNCommandBarCommand.allCases.filter {
            $0.rawValue.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Result sheet presented above command list
            if viewModel.isCommandBarPresented, let result = viewModel.commandBarResult {
                commandResultSheet(result: result)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider()

            // Command list
            commandList
                .animation(reduceMotion ? nil : .default, value: filteredCommands.map(\.id))

            // Query field
            queryField
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .background(reduceTransparency ? Color(.systemBackground) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .onAppear { isQueryFocused = true }
    }

    // MARK: - Query Field

    private var queryField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Type a command or /\u{2026}", text: $query)
                .focused($isQueryFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Command search field")
        }
        .padding(10)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Command List

    private var commandList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredCommands) { command in
                    commandRow(command)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 260)
    }

    private func commandRow(_ command: CNCommandBarCommand) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                query = ""
            }
            Task { await viewModel.handleCommand(command, noteText: noteText) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: command.sfSymbol)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(command.displayName)
                        .font(.subheadline.weight(.medium))
                    Text(command.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(command.displayName): \(command.description)")
    }

    // MARK: - Command Result Sheet

    @ViewBuilder
    private func commandResultSheet(result: CNCommandBarResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label(result.command.displayName, systemImage: result.command.sfSymbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Button {
                    viewModel.dismissCommandBarResult()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss result")
            }

            Divider()

            // Editable result text
            TextEditor(text: Binding(
                get: { result.displayText },
                set: { viewModel.editCommandBarResult(newText: $0) }
            ))
            .font(.body)
            .frame(minHeight: 80, maxHeight: 180)
            .scrollContentBackground(.hidden)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("AI-generated result. Edit before inserting.")

            // Provenance
            CNProvenanceRow(label: result.provenance)

            // Approval controls
            HStack(spacing: 12) {
                Button {
                    viewModel.approveCommandBarResult()
                } label: {
                    Text("Insert into note")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Insert this result into your note")

                Button {
                    viewModel.dismissCommandBarResult()
                } label: {
                    Text("Discard")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Discard this result without inserting")
            }
        }
        .padding()
    }
}

// MARK: - Command Bar Trigger Button

// Lightweight button to embed in the Church Notes toolbar.
struct ChurchNotesCommandBarButton: View {
    @ObservedObject var viewModel: ChurchNotesContextViewModel
    let noteText: String
    @State private var isPresented = false
    private let flags = AMENFeatureFlags.shared

    var body: some View {
        if flags.churchNotesCommandBarEnabled {
            Button {
                isPresented.toggle()
            } label: {
                Image(systemName: "command")
                    .accessibilityLabel("Open command bar")
            }
            .sheet(isPresented: $isPresented) {
                ChurchNotesCommandBarView(viewModel: viewModel, noteText: noteText)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}
