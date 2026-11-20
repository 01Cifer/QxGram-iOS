import Foundation

public enum QxGramScreenshotPolicy {
    public static let keyPrefix = "qxgram.settings."

    public static func key(accountId: AccountRecordId) -> String {
        return "\(Self.keyPrefix)\(accountId.int64).allowScreenshots"
    }

    public static func isAllowed(accountId: AccountRecordId) -> Bool {
        return UserDefaults.standard.bool(forKey: self.key(accountId: accountId))
    }

    public static func shouldProtect(isSecret: Bool, screenshotsAllowed: Bool) -> Bool {
        return isSecret && !screenshotsAllowed
    }
}
