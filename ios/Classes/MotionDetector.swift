import CoreMotion
import Foundation

// MARK: - Activity Type

/// Recognized motion activity types reported to Dart.
enum DetectedActivity: String {
    case still
    case walking
    case running
    case on_bicycle
    case in_vehicle
    case unknown
}

// MARK: - MotionDetectorService

/// Production motion detector using CMMotionActivityManager + accelerometer.
///
/// Features:
/// - Real activity recognition (walking, running, automotive, cycling, stationary)
/// - Confidence reporting per activity (0-100 scale for Dart compatibility)
/// - Accelerometer-based motion/stillness detection as fallback
/// - Configurable motion trigger delay
/// - Callbacks for motion state changes and activity changes
final class MotionDetectorService {

    // MARK: - Public Callbacks

    /// Called when motion state changes (moving vs stationary).
    typealias MotionChangeHandler = (Bool) -> Void
    /// Called when the detected activity type changes. Dict matches Dart ActivityEvent.fromMap():
    /// { "activity": String, "confidence": Int (0-100) }
    typealias ActivityChangeHandler = ([String: Any]) -> Void

    // MARK: - Properties

    private let activityManager = CMMotionActivityManager()
    private let motionManager = CMMotionManager()

    private var motionChangeCallback: MotionChangeHandler?
    private var activityChangeCallback: ActivityChangeHandler?
    private var isRunning = false

    // State
    private var currentActivity: DetectedActivity = .unknown
    private var isMoving = false

    // Config
    private var motionTriggerDelay: TimeInterval = 0
    private var disableMotionActivityUpdates = false

    // Accelerometer
    private let accelerometerUpdateInterval: TimeInterval = 0.5
    private let motionThreshold: Double = 0.15  // g-force deviation from 1.0
    private var accelStillCount = 0
    private var accelMoveCount = 0
    private let accelWindowSize = 6  // samples to confirm state change

    // Delayed trigger
    private var motionTriggerTimer: Timer?

    // MARK: - Start / Stop

    func start(
        motionTriggerDelay: TimeInterval = 0,
        disableMotionActivityUpdates: Bool = false,
        onMotionChanged: @escaping MotionChangeHandler,
        onActivityChanged: ActivityChangeHandler? = nil
    ) {
        guard !isRunning else { return }
        isRunning = true
        isMoving = false
        currentActivity = .unknown
        self.motionTriggerDelay = motionTriggerDelay
        self.disableMotionActivityUpdates = disableMotionActivityUpdates
        self.motionChangeCallback = onMotionChanged
        self.activityChangeCallback = onActivityChanged

        startActivityUpdates()
        startAccelerometerUpdates()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        activityManager.stopActivityUpdates()
        motionManager.stopAccelerometerUpdates()
        motionTriggerTimer?.invalidate()
        motionTriggerTimer = nil

        motionChangeCallback = nil
        activityChangeCallback = nil
    }

    /// Update configuration without full restart.
    func configure(motionTriggerDelay: TimeInterval? = nil,
                   disableMotionActivityUpdates: Bool? = nil) {
        if let d = motionTriggerDelay { self.motionTriggerDelay = d }
        if let v = disableMotionActivityUpdates {
            self.disableMotionActivityUpdates = v
            if v {
                activityManager.stopActivityUpdates()
            } else if isRunning {
                startActivityUpdates()
            }
        }
    }

    // MARK: - CMMotionActivity

    private func startActivityUpdates() {
        guard !disableMotionActivityUpdates,
              CMMotionActivityManager.isActivityAvailable()
        else { return }

        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self = self, let activity = activity else { return }
            self.processActivity(activity)
        }
    }

    private func processActivity(_ activity: CMMotionActivity) {
        let (detected, confidence) = classifyActivity(activity)

        // Only report if activity type actually changed
        if detected != currentActivity {
            currentActivity = detected

            // Emit with keys matching Dart ActivityEvent.fromMap():
            // "activity" (String) and "confidence" (Int, 0-100)
            activityChangeCallback?([
                "activity": detected.rawValue,
                "confidence": confidence,
            ])
        }

        // Determine motion state from activity
        let activityMoving: Bool
        switch detected {
        case .walking, .running, .on_bicycle, .in_vehicle:
            activityMoving = true
        case .still:
            activityMoving = false
        case .unknown:
            return  // Don't change state on unknown
        }

        if activityMoving != isMoving {
            handleMotionStateChange(moving: activityMoving)
        }
    }

    /// Classifies CMMotionActivity and returns (type, confidence_0_to_100).
    private func classifyActivity(_ activity: CMMotionActivity) -> (DetectedActivity, Int) {
        // Convert CMMotionActivityConfidence to 0-100 scale
        let confidence: Int
        switch activity.confidence {
        case .low: confidence = 33
        case .medium: confidence = 66
        case .high: confidence = 100
        @unknown default: confidence = 0
        }

        if activity.stationary {
            return (.still, confidence)
        } else if activity.automotive {
            return (.in_vehicle, confidence)
        } else if activity.running {
            return (.running, confidence)
        } else if activity.cycling {
            return (.on_bicycle, confidence)
        } else if activity.walking {
            return (.walking, confidence)
        }
        return (.unknown, 0)
    }

    // MARK: - Accelerometer Fallback

    private func startAccelerometerUpdates() {
        guard motionManager.isAccelerometerAvailable else { return }

        motionManager.accelerometerUpdateInterval = accelerometerUpdateInterval

        motionManager.startAccelerometerUpdates(to: OperationQueue()) { [weak self] data, error in
            guard let self = self, let data = data, error == nil else { return }
            self.processAccelerometer(data)
        }
    }

    private func processAccelerometer(_ data: CMAccelerometerData) {
        let x = data.acceleration.x
        let y = data.acceleration.y
        let z = data.acceleration.z
        let magnitude = sqrt(x * x + y * y + z * z)
        let deviation = abs(magnitude - 1.0)

        if deviation > motionThreshold {
            accelMoveCount += 1
            accelStillCount = 0
        } else {
            accelStillCount += 1
            accelMoveCount = 0
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.accelMoveCount >= self.accelWindowSize && !self.isMoving {
                self.handleMotionStateChange(moving: true)
            } else if self.accelStillCount >= self.accelWindowSize * 2 && self.isMoving {
                self.handleMotionStateChange(moving: false)
            }
        }
    }

    // MARK: - State Change Handling

    private func handleMotionStateChange(moving: Bool) {
        motionTriggerTimer?.invalidate()
        motionTriggerTimer = nil

        if motionTriggerDelay > 0 && moving {
            motionTriggerTimer = Timer.scheduledTimer(
                withTimeInterval: motionTriggerDelay,
                repeats: false
            ) { [weak self] _ in
                self?.commitMotionChange(moving: true)
            }
        } else {
            commitMotionChange(moving: moving)
        }
    }

    private func commitMotionChange(moving: Bool) {
        guard moving != isMoving else { return }
        isMoving = moving
        motionChangeCallback?(moving)
    }
}
