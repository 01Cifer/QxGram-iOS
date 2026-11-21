import Foundation

public enum QxGramTtlPolicy {
    public static let keyPrefix = "qxgram.settings."
    private static let fuseKeySuffix = "ttlFuseTripped"

    public static func key(accountId: AccountRecordId, setting: String) -> String {
        return "\(Self.keyPrefix)\(accountId.int64).\(setting)"
    }

    public static func fuseKey(accountId: AccountRecordId) -> String {
        return Self.key(accountId: accountId, setting: Self.fuseKeySuffix)
    }

    public static func isEmergencyDisabled() -> Bool {
        return QxGramLaunchSafety.isEmergencyMode()
    }

    public static func isTtlDisabled(accountId: AccountRecordId) -> Bool {
        return Self.isEmergencyDisabled() || UserDefaults.standard.bool(forKey: Self.fuseKey(accountId: accountId))
    }

    public static func disableTtl(accountId: AccountRecordId) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Self.fuseKey(accountId: accountId))
        defaults.set(false, forKey: Self.key(accountId: accountId, setting: "saveTtlMedia"))
        defaults.set(false, forKey: Self.key(accountId: accountId, setting: "showTtl"))
    }

    public static func isSaveMediaEnabled(accountId: AccountRecordId) -> Bool {
        guard !Self.isTtlDisabled(accountId: accountId) else {
            return false
        }
        return UserDefaults.standard.bool(forKey: self.key(accountId: accountId, setting: "saveTtlMedia"))
    }

    public static func isShowTtlEnabled(accountId: AccountRecordId) -> Bool {
        guard !Self.isTtlDisabled(accountId: accountId) else {
            return false
        }
        return UserDefaults.standard.bool(forKey: self.key(accountId: accountId, setting: "showTtl"))
    }
}
