import Foundation
import SwiftUI

/// A toast item with unique identity for queue management.
struct ToastItem: Identifiable {
    let id = UUID()
    let message: String
    let type: ToastType
}

/// Manages a toast notification queue with auto-dismiss after 5 seconds.
@MainActor
@Observable
final class ToastManager {
    var currentToast: ToastItem?

    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, type: ToastType = .error) {
        dismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.25)) {
            currentToast = ToastItem(message: message, type: type)
        }
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.25)) {
            currentToast = nil
        }
    }
}
