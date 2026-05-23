import Foundation

/// Browser-style back/forward history for the settings window. Tracks the
/// sequence of visited sections and a cursor into it. `record` extends history
/// when the user navigates forward; `goBack`/`goForward` replay existing entries
/// without disturbing the stack — exactly like macOS System Settings.
struct SettingsNavigationHistory: Equatable {
    private(set) var entries: [SettingsSection]
    private(set) var index: Int

    init(initial: SettingsSection) {
        entries = [initial]
        index = 0
    }

    var current: SettingsSection {
        entries[index]
    }

    var canGoBack: Bool {
        index > 0
    }

    var canGoForward: Bool {
        index < entries.count - 1
    }

    /// Records a forward navigation to `section`. No-op when it equals the
    /// current entry. Any forward entries beyond the cursor are discarded
    /// (standard browser semantics) before appending.
    mutating func record(_ section: SettingsSection) {
        guard section != current else { return }
        if index < entries.count - 1 {
            entries.removeSubrange((index + 1)...)
        }
        entries.append(section)
        index = entries.count - 1
    }

    /// Moves the cursor back one entry and returns it, or `nil` at the start.
    mutating func goBack() -> SettingsSection? {
        guard canGoBack else { return nil }
        index -= 1
        return entries[index]
    }

    /// Moves the cursor forward one entry and returns it, or `nil` at the tip.
    mutating func goForward() -> SettingsSection? {
        guard canGoForward else { return nil }
        index += 1
        return entries[index]
    }
}
