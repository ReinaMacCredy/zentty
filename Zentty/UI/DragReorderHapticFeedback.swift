import AppKit

@MainActor
protocol DragReorderHapticFeedbackPerforming {
    func performReorderAlignmentFeedback()
    func performStructuralChangeFeedback()
}

@MainActor
struct DragReorderHapticFeedbackPerformer: DragReorderHapticFeedbackPerforming {
    func performReorderAlignmentFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    func performStructuralChangeFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
    }
}
