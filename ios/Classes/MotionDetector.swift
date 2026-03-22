import CoreMotion

/// Motion detector using CMMotionActivityManager.
/// Reduces GPS polling when stationary, increases when moving.
class MotionDetectorService {
    private let activityManager = CMMotionActivityManager()
    private let motionManager = CMMotionManager()
    private var callback: ((Bool) -> Void)?
    private var isRunning = false

    func start(onMotionChanged: @escaping (Bool) -> Void) {
        guard !isRunning else { return }
        isRunning = true
        callback = onMotionChanged

        guard CMMotionActivityManager.isActivityAvailable() else { return }

        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity = activity else { return }

            if activity.stationary {
                self?.callback?(false)
            } else if activity.walking || activity.running || activity.automotive || activity.cycling {
                self?.callback?(true)
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        activityManager.stopActivityUpdates()
        callback = nil
    }
}
