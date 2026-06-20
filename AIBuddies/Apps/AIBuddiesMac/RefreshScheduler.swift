import Foundation

/// Fires a periodic tick on the main run loop at the configured interval.
@MainActor
final class RefreshScheduler {
    private var timer: Timer?
    private let onTick: () -> Void

    init(onTick: @escaping () -> Void) { self.onTick = onTick }

    func start(interval: TimeInterval) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.onTick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit { timer?.invalidate() }
}
