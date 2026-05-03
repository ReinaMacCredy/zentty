import AppKit
import SwiftUI

@MainActor
enum BookmarkSaveSheetController {
    static func present(
        in parent: NSWindow?,
        initialTemplate: WorkspaceTemplate,
        isUpdatingExisting: Bool,
        onSave: @escaping (WorkspaceTemplate) -> Void
    ) {
        guard let parent else { return }

        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 390),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        sheet.title = isUpdatingExisting ? "Edit Bookmark" : "Save Worklane"
        sheet.isReleasedWhenClosed = false

        let viewModel = BookmarkSaveSheetViewModel(
            initialTemplate: initialTemplate,
            isUpdatingExisting: isUpdatingExisting,
            onSave: { template in
                onSave(template)
                parent.endSheet(sheet, returnCode: .OK)
            },
            onCancel: {
                parent.endSheet(sheet, returnCode: .cancel)
            }
        )

        let host = NSHostingController(rootView: BookmarkSaveSheetView(viewModel: viewModel))
        sheet.contentViewController = host

        parent.beginSheet(sheet) { _ in
            sheet.contentViewController = nil
        }
    }
}

@MainActor
final class BookmarkSaveSheetViewModel: ObservableObject {
    @Published var name: String
    @Published var kind: WorkspaceTemplate.Kind
    @Published var paneRows: [PaneRow]

    let isUpdatingExisting: Bool
    let onSave: (WorkspaceTemplate) -> Void
    let onCancel: () -> Void

    private var template: WorkspaceTemplate

    struct PaneRow: Identifiable {
        let id: String
        let columnID: String
        let workingDirectory: String?
        let detectedCommand: String?
        var commandText: String
        var environmentText: String
        var wasUserEdited: Bool
    }

    init(
        initialTemplate: WorkspaceTemplate,
        isUpdatingExisting: Bool,
        onSave: @escaping (WorkspaceTemplate) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.template = initialTemplate
        self.name = initialTemplate.name
        self.kind = initialTemplate.kind
        self.isUpdatingExisting = isUpdatingExisting
        self.onSave = onSave
        self.onCancel = onCancel
        self.paneRows = initialTemplate.columns.flatMap { column in
            column.panes.map { pane in
                PaneRow(
                    id: pane.id,
                    columnID: column.id,
                    workingDirectory: pane.workingDirectory,
                    detectedCommand: pane.command,
                    commandText: pane.command ?? "",
                    environmentText: Self.encodeEnvironment(pane.environment),
                    wasUserEdited: pane.wasUserEdited
                )
            }
        }
    }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var primaryActionTitle: String {
        guard !isUpdatingExisting else { return "Update" }

        switch kind {
        case .bookmark:
            return "Save Bookmark"
        case .preset:
            return "Save Preset"
        }
    }

    var commandSummary: String {
        let paneCount = paneRows.count
        let paneNoun = paneCount == 1 ? "pane" : "panes"
        let customCommandCount = paneRows.filter { row in
            !row.commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count

        guard customCommandCount > 0 else {
            return "\(paneCount) \(paneNoun) will reopen with the default shell"
        }

        if customCommandCount == 1 {
            return "1 pane has a custom command"
        }
        return "\(customCommandCount) panes have custom commands"
    }

    func save() {
        var updated = template
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.kind = kind
        updated.updatedAt = Date()

        let rowsByPaneID = Dictionary(uniqueKeysWithValues: paneRows.map { ($0.id, $0) })
        updated.columns = updated.columns.map { column in
            var column = column
            column.panes = column.panes.map { pane in
                var pane = pane
                if let row = rowsByPaneID[pane.id] {
                    let trimmedCommand = row.commandText.trimmingCharacters(in: .whitespacesAndNewlines)
                    pane.command = trimmedCommand.isEmpty ? nil : trimmedCommand
                    pane.environment = decodeEnvironment(row.environmentText)
                    // Preserve user-edited intent: once edited, always edited
                    // (until the user clears the field). Prevents Update Bookmark
                    // from silently wiping flags like `--yolo`.
                    let differsFromDetected = row.commandText != (row.detectedCommand ?? "")
                    pane.wasUserEdited = row.wasUserEdited || differsFromDetected
                }
                if kind == .preset {
                    pane.workingDirectory = nil
                }
                return pane
            }
            return column
        }

        if kind == .preset {
            updated.projectRoot = nil
        }

        onSave(updated)
    }

    func cancel() {
        onCancel()
    }

    static func encodeEnvironment(_ environment: [String: String]) -> String {
        environment
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
    }

    private func decodeEnvironment(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = String(parts[1])
            guard !key.isEmpty else { continue }
            result[key] = value
        }
        return result
    }
}

struct BookmarkSaveSheetKindPresentation: Equatable {
    let kind: WorkspaceTemplate.Kind
    let title: String
    let subtitle: String
    let symbolName: String

    init(kind: WorkspaceTemplate.Kind) {
        self.kind = kind
        switch kind {
        case .bookmark:
            title = "Bookmark"
            subtitle = "Restore panes in these folders"
            symbolName = "bookmark.fill"
        case .preset:
            title = "Preset"
            subtitle = "Restore panes without folders"
            symbolName = "rectangle.split.3x1"
        }
    }
}

struct BookmarkSaveSheetCommandsDisclosurePresentation: Equatable {
    enum ExpandedContentTransition: Equatable {
        case fadeInPlace
    }

    let animationDuration: Double
    let expandedContentTransition: ExpandedContentTransition

    static let standard = Self(
        animationDuration: 0.16,
        expandedContentTransition: .fadeInPlace
    )

    var animation: Animation {
        .easeInOut(duration: animationDuration)
    }

    var transition: AnyTransition {
        switch expandedContentTransition {
        case .fadeInPlace:
            return .opacity
        }
    }
}

struct BookmarkSaveSheetView: View {
    @ObservedObject var viewModel: BookmarkSaveSheetViewModel
    @State private var hoveredKind: WorkspaceTemplate.Kind?
    @State private var isCommandsExpanded = false
    @State private var isCommandsHovered = false

    private static let selectableKinds: [WorkspaceTemplate.Kind] = [.bookmark, .preset]
    private let commandsDisclosurePresentation = BookmarkSaveSheetCommandsDisclosurePresentation.standard

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    nameField
                    kindSelector
                    Divider()
                    commandsSection
                }
                .padding(20)
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: viewModel.cancel)
                    .keyboardShortcut(.cancelAction)
                Button(viewModel.primaryActionTitle, action: viewModel.save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canSave)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 480, height: 390)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Name")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            TextField("Untitled", text: $viewModel.name)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var kindSelector: some View {
        HStack(spacing: 8) {
            ForEach(Self.selectableKinds, id: \.rawValue) { kind in
                kindOption(kind)
            }
        }
    }

    private func kindOption(_ kind: WorkspaceTemplate.Kind) -> some View {
        let presentation = BookmarkSaveSheetKindPresentation(kind: kind)
        let isSelected = viewModel.kind == kind
        let isHovered = hoveredKind == kind

        return Button {
            viewModel.kind = kind
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: presentation.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(presentation.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(kindOptionBackgroundColor(isSelected: isSelected, isHovered: isHovered))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color.primary.opacity(isHovered ? 0.18 : 0.10),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredKind = hovering ? kind : nil
        }
    }

    private func kindOptionBackgroundColor(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(isHovered ? 0.18 : 0.14)
        }
        return Color.primary.opacity(isHovered ? 0.06 : 0.035)
    }

    private var commandsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(commandsDisclosurePresentation.animation) {
                    isCommandsExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isCommandsExpanded ? 90 : 0))
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Commands")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(viewModel.commandSummary)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isCommandsHovered = hovering
            }

            if isCommandsExpanded {
                paneList
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
                    .padding(.bottom, 12)
                    .transition(commandsDisclosurePresentation.transition)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isCommandsHovered ? 0.055 : 0.035))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(isCommandsHovered ? 0.16 : 0.10), lineWidth: 1)
        }
    }

    private var paneList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(viewModel.paneRows.enumerated()), id: \.element.id) { index, _ in
                paneRow(index: index)
            }
        }
    }

    private func paneRow(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pane \(index + 1)")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if viewModel.kind == .bookmark, let cwd = viewModel.paneRows[index].workingDirectory {
                    Text(cwd)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            TextField(
                "(shell)",
                text: $viewModel.paneRows[index].commandText
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))
            if let detected = viewModel.paneRows[index].detectedCommand {
                Text("detected: \(detected)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else {
                Text("detected: shell")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
}
