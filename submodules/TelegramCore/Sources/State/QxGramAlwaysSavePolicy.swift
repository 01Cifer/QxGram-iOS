import Foundation

public enum QxGramAlwaysSavePolicy {
    public static func isEnabled(accountId: AccountRecordId) -> Bool {
        return UserDefaults.standard.bool(forKey: QxGramTtlPolicy.key(accountId: accountId, setting: "alwaysSave"))
    }
}
