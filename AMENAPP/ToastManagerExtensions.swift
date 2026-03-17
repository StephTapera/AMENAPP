import Combine

/// Extensions to existing ToastManager for undo support
extension ToastManager {
    /// Show toast with undo action
    func showWithUndo(_ message: String, undoHandler: @escaping () -> Void) {
        let toast = ToastNotification(
            message: message,
            style: .info,
            action: undoHandler,
            actionLabel: "Undo"
        )
        show(toast, duration: 5.0)
    }
    
    /// Show success message (convenience wrapper)
    func success(_ message: String) {
        showSuccess(message)
    }
    
    /// Show info message (convenience wrapper)
    func info(_ message: String) {
        showInfo(message)
    }
}
