import SwiftUI

struct BookmarksPopoverView: View {
    @ObservedObject var viewModel: BookmarksPopoverViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.hasAnyTemplates {
                searchField
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        section(title: "Bookmarks", items: viewModel.bookmarks)
                        section(title: "Presets", items: viewModel.presets)
                        if viewModel.isEmptyAfterFiltering {
                            Text("No matches.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        }
                    }
                }
                .frame(maxHeight: BookmarksPopoverMetrics.populatedMaxHeight)
            } else {
                emptyState
                    .frame(height: BookmarksPopoverMetrics.emptyStateHeight)
            }
        }
        .frame(width: BookmarksPopoverMetrics.contentWidth)
        .onAppear { isSearchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            TextField("Search bookmarks & presets…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFocused)
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            Menu {
                Button("Bookmark Current Worklane…") {
                    viewModel.saveCurrentWorklane(as: .bookmark)
                }
                .disabled(!viewModel.canSaveCurrentWorklane())
                Button("Save Current as Preset…") {
                    viewModel.saveCurrentWorklane(as: .preset)
                }
                .disabled(!viewModel.canSaveCurrentWorklane())
                Divider()
                Button("Import Preset…") {
                    viewModel.importPreset()
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func section(title: String, items: [WorkspaceTemplate]) -> some View {
        if !items.isEmpty {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ForEach(items) { template in
                row(for: template)
            }
        }
    }

    private func row(for template: WorkspaceTemplate) -> some View {
        BookmarkRow(template: template) {
            viewModel.activate(template)
        } onMenuAction: { action in
            viewModel.performMenuAction(action, on: template)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bookmark")
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(.secondary)
            Text("No bookmarks or presets yet")
                .font(.system(size: 14, weight: .semibold))
            Text("Save a worklane setup to relaunch it instantly.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                viewModel.saveCurrentWorklane(as: .bookmark)
            } label: {
                Text("Bookmark current worklane")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!viewModel.canSaveCurrentWorklane())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }
}

private struct BookmarkRow: View {
    let template: WorkspaceTemplate
    let onActivate: () -> Void
    let onMenuAction: (BookmarksPopoverViewModel.TemplateAction) -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 10) {
                Image(systemName: template.kind == .bookmark ? "bookmark.fill" : "rectangle.stack")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(template.pinned ? .accentColor : .secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(template.name.isEmpty ? "Untitled" : template.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if template.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isHovering ? Color.primary.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Rename…") { onMenuAction(.rename) }
            Button("Edit…") { onMenuAction(.edit) }
            Button("Duplicate") { onMenuAction(.duplicate) }
            Divider()
            Button(template.pinned ? "Unpin" : "Pin to top") { onMenuAction(.togglePin) }
            Button(template.kind == .bookmark ? "Save as Preset…" : "Bookmark in current worklane…") {
                onMenuAction(.convert)
            }
            if template.kind == .bookmark {
                Button("Reveal in Finder") { onMenuAction(.revealInFinder) }
            }
            Divider()
            Button("Export as Preset…") { onMenuAction(.exportAsPreset) }
            Divider()
            Button("Delete", role: .destructive) { onMenuAction(.delete) }
        }
    }

    private var subtitle: String? {
        switch template.kind {
        case .bookmark:
            if let root = template.projectRoot {
                return abbreviatedPath(root)
            }
            return paneSummary
        case .preset:
            return paneSummary
        }
    }

    private var paneSummary: String? {
        let count = template.paneCount
        guard count > 0 else { return nil }
        let commands = template.allPanes.compactMap { $0.command }.prefix(2)
        if commands.isEmpty {
            return "\(count) \(count == 1 ? "pane" : "panes")"
        }
        let commandList = commands.joined(separator: ", ")
        return "\(count) \(count == 1 ? "pane" : "panes") · \(commandList)"
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
