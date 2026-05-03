import Foundation
import OSLog

@MainActor
final class BookmarkRestoreLogger {
    static let shared = BookmarkRestoreLogger()

    private let logger = Logger(subsystem: "be.zenjoy.zentty", category: "BookmarkRestore")

    private init() {}

    func logFallbacks(
        _ fallbacks: [WorkspaceTemplateImporter.Fallback],
        worklaneID: WorklaneID
    ) {
        guard !fallbacks.isEmpty else { return }
        for fallback in fallbacks {
            switch fallback.kind {
            case .missingWorkingDirectory(let requested, let fellBackTo):
                logger.warning(
                    "Bookmark restore for worklane \(worklaneID.rawValue, privacy: .public): pane \(fallback.paneID.rawValue, privacy: .public) requested cwd \(requested, privacy: .public) which no longer exists; fell back to \(fellBackTo, privacy: .public)"
                )
            case .missingCommand(let command):
                logger.warning(
                    "Bookmark restore for worklane \(worklaneID.rawValue, privacy: .public): pane \(fallback.paneID.rawValue, privacy: .public) command \(command, privacy: .public) is not on PATH; using prefillText (no auto-Enter)"
                )
            }
        }
    }
}
