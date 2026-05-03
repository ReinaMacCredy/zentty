import Combine
import Foundation

@MainActor
final class BookmarksPopoverViewModel: ObservableObject {
    @Published private(set) var bookmarks: [WorkspaceTemplate] = []
    @Published private(set) var presets: [WorkspaceTemplate] = []
    @Published var query: String = "" {
        didSet { rebuild() }
    }

    let store: BookmarkStore
    let canSaveCurrentWorklane: () -> Bool
    let onActivate: (WorkspaceTemplate) -> Void
    let onSaveCurrentWorklane: (WorkspaceTemplate.Kind) -> Void
    let onImportPreset: () -> Void
    let onDismiss: () -> Void
    let onTemplateMenuAction: (TemplateAction, WorkspaceTemplate) -> Void

    enum TemplateAction {
        case rename
        case edit
        case duplicate
        case delete
        case convert
        case revealInFinder
        case togglePin
        case exportAsPreset
    }

    private var observerToken: UUID?

    init(
        store: BookmarkStore,
        canSaveCurrentWorklane: @escaping () -> Bool,
        onActivate: @escaping (WorkspaceTemplate) -> Void,
        onSaveCurrentWorklane: @escaping (WorkspaceTemplate.Kind) -> Void,
        onImportPreset: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onTemplateMenuAction: @escaping (TemplateAction, WorkspaceTemplate) -> Void
    ) {
        self.store = store
        self.canSaveCurrentWorklane = canSaveCurrentWorklane
        self.onActivate = onActivate
        self.onSaveCurrentWorklane = onSaveCurrentWorklane
        self.onImportPreset = onImportPreset
        self.onDismiss = onDismiss
        self.onTemplateMenuAction = onTemplateMenuAction
        rebuild()
        observerToken = store.addObserver { [weak self] in
            self?.rebuild()
        }
    }

    deinit {
        if let token = observerToken {
            // BookmarkStore is @MainActor; this deinit may run off-main, but
            // observer removal is safe to perform via a Task hop.
            let store = store
            Task { @MainActor in
                store.removeObserver(token)
            }
        }
    }

    func activate(_ template: WorkspaceTemplate) {
        onActivate(template)
        store.recordUse(id: template.id)
        onDismiss()
    }

    func saveCurrentWorklane(as kind: WorkspaceTemplate.Kind) {
        guard canSaveCurrentWorklane() else { return }
        onSaveCurrentWorklane(kind)
        onDismiss()
    }

    func importPreset() {
        onImportPreset()
        onDismiss()
    }

    func performMenuAction(_ action: TemplateAction, on template: WorkspaceTemplate) {
        onTemplateMenuAction(action, template)
    }

    var hasAnyTemplates: Bool {
        !store.templates.isEmpty
    }

    var isEmptyAfterFiltering: Bool {
        bookmarks.isEmpty && presets.isEmpty
    }

    private func rebuild() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let templates = store.templates
        let filtered: [(template: WorkspaceTemplate, score: Double)] = templates.compactMap { template in
            guard !trimmedQuery.isEmpty else {
                return (template, 0)
            }
            let haystack = [template.name, template.projectRoot ?? "", template.title ?? ""]
                .joined(separator: " ")
                .lowercased()
            let score = FuzzyMatcher.score(query: trimmedQuery, in: haystack)
            return score > 0 ? (template, score) : nil
        }

        let sorted = filtered.sorted { lhs, rhs in
            if lhs.template.pinned != rhs.template.pinned {
                return lhs.template.pinned
            }
            if !trimmedQuery.isEmpty, lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            switch (lhs.template.lastUsedAt, rhs.template.lastUsedAt) {
            case (let a?, let b?):
                if a != b { return a > b }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }
            return lhs.template.name.localizedCaseInsensitiveCompare(rhs.template.name) == .orderedAscending
        }

        bookmarks = sorted.compactMap { $0.template.kind == .bookmark ? $0.template : nil }
        presets = sorted.compactMap { $0.template.kind == .preset ? $0.template : nil }
    }
}
