import Foundation

enum WorkspaceTemplateCapture {
    private static let shellProcessNames: Set<String> = [
        "zsh", "bash", "sh", "fish", "dash", "ksh", "tcsh", "csh",
        "-zsh", "-bash", "-sh", "-fish", "-dash", "-ksh", "-tcsh", "-csh",
        "login",
    ]

    static func capture(
        worklane: WorklaneState,
        kind: WorkspaceTemplate.Kind,
        name: String
    ) -> WorkspaceTemplate {
        let columns = worklane.paneStripState.columns.map { column -> WorkspaceTemplate.Column in
            let panes = column.panes.map { pane -> WorkspaceTemplate.Pane in
                makePane(
                    pane: pane,
                    auxiliary: worklane.auxiliaryStateByPaneID[pane.id],
                    kind: kind
                )
            }
            return WorkspaceTemplate.Column(
                id: column.id.rawValue,
                width: Double(column.width),
                focusedPaneID: column.focusedPaneID?.rawValue,
                lastFocusedPaneID: column.lastFocusedPaneID?.rawValue,
                paneHeights: column.paneHeights.map(Double.init),
                panes: panes
            )
        }

        let cwds = columns
            .flatMap(\.panes)
            .compactMap(\.workingDirectory)
        let projectRoot = kind == .bookmark ? longestCommonAncestor(of: cwds) : nil

        return WorkspaceTemplate(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            title: WorklaneState.meaningfulTitle(from: worklane.title),
            color: worklane.color?.rawValue,
            projectRoot: projectRoot,
            nextPaneNumber: worklane.nextPaneNumber,
            focusedColumnID: worklane.paneStripState.focusedColumnID?.rawValue,
            columns: columns
        )
    }

    private static func makePane(
        pane: PaneState,
        auxiliary: PaneAuxiliaryState?,
        kind: WorkspaceTemplate.Kind
    ) -> WorkspaceTemplate.Pane {
        let workingDirectory: String? = {
            guard kind == .bookmark else {
                return nil
            }
            return trimmed(auxiliary?.metadata?.currentWorkingDirectory)
                ?? trimmed(auxiliary?.presentation.cwd)
                ?? trimmed(pane.sessionRequest.workingDirectory)
        }()

        return WorkspaceTemplate.Pane(
            id: pane.id.rawValue,
            titleSeed: trimmed(auxiliary?.presentation.rememberedTitle) ?? trimmed(pane.title),
            workingDirectory: workingDirectory,
            command: detectedCommand(auxiliary: auxiliary),
            environment: pane.sessionRequest.environmentVariables,
            wasUserEdited: false
        )
    }

    private static func detectedCommand(auxiliary: PaneAuxiliaryState?) -> String? {
        let processName = trimmed(auxiliary?.metadata?.processName)
        guard let processName,
              !shellProcessNames.contains(processName.lowercased()) else {
            return nil
        }
        return processName
    }

    static func longestCommonAncestor(of paths: [String]) -> String? {
        let normalized = paths
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .filter { !$0.isEmpty }
        guard let first = normalized.first else {
            return nil
        }
        if normalized.count == 1 {
            return first
        }

        let firstComponents = pathComponents(first)
        var commonPrefixLength = firstComponents.count
        for path in normalized.dropFirst() {
            let components = pathComponents(path)
            commonPrefixLength = min(commonPrefixLength, components.count)
            var matched = 0
            while matched < commonPrefixLength && firstComponents[matched] == components[matched] {
                matched += 1
            }
            commonPrefixLength = matched
            if commonPrefixLength == 0 {
                return nil
            }
        }

        guard commonPrefixLength > 0 else {
            return nil
        }
        let prefix = Array(firstComponents.prefix(commonPrefixLength))
        let joined = "/" + prefix.joined(separator: "/")
        return joined.isEmpty ? "/" : joined
    }

    private static func pathComponents(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
