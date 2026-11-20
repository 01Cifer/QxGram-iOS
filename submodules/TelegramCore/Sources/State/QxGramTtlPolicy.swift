import Foundation

public enum QxGramTtlPolicy {
    public static let keyPrefix = "qxgram.settings."

    public static func key(accountId: AccountRecordId, setting: String) -> String {
        return "\(Self.keyPrefix)\(accountId.int64).\(setting)"
    }

    public static func isSaveMediaEnabled(accountId: AccountRecordId) -> Bool {
        return UserDefaults.standard.bool(forKey: self.key(accountId: accountId, setting: "saveTtlMedia"))
    }

    public static func isShowTtlEnabled(accountId: AccountRecordId) -> Bool {
        return UserDefaults.standard.bool(forKey: self.key(accountId: accountId, setting: "showTtl"))
    }
}
