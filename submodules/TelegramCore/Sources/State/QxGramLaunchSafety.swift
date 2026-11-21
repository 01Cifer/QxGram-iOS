import Foundation

public enum QxGramLaunchSafety {
    private static let lastAttemptKey = "qxgram.launch.lastAttempt"
    private static let fastFailuresKey = "qxgram.launch.fastFailures"
    private static let emergencyKey = "qxgram.emergency.ttlDisabled"
    private static let noticeKey = "qxgram.emergency.ttlNoticePending"
    private static let fastLaunchWindow: TimeInterval = 120.0

    public static func recordLaunchAttempt() {
        let defaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        let previous = defaults.double(forKey: Self.lastAttemptKey)
        let failures: Int
        if previous > 0.0, now - previous < Self.fastLaunchWindow {
            failures = defaults.integer(forKey: Self.fastFailuresKey) + 1
        } else {
            failures = 0
        }
        defaults.set(now, forKey: Self.lastAttemptKey)
        defaults.set(failures, forKey: Self.fastFailuresKey)

        if failures >= 2 {
            defaults.set(true, forKey: Self.emergencyKey)
            defaults.set(true, forKey: Self.noticeKey)
            Logger.shared.log("QxGram Launch", "two fast failed launches: TTL and deleted-message archive disabled")
        }
    }

    public static func markLaunchStable() {
        let defaults = UserDefaults.standard
        defaults.set(0, forKey: Self.fastFailuresKey)
        defaults.set(0.0, forKey: Self.lastAttemptKey)
    }

    public static func isEmergencyMode() -> Bool {
        return UserDefaults.standard.bool(forKey: Self.emergencyKey)
    }

    public static func consumePendingNotice() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.noticeKey) else {
            return false
        }
        defaults.set(false, forKey: Self.noticeKey)
        return true
    }
}
