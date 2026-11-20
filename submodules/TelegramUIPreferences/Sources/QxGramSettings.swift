import Foundation
import TelegramCore

public extension Notification.Name {
    static let qxGramSettingsDidChange = Notification.Name("QxGramSettingsDidChange")
}

public enum QxGramSetting: String {
    case ghost
    case showDeletedMessages
    case saveTtlMedia
    case showTtl
    case allowScreenshots
}

public final class QxGramSettings {
    private static let keyPrefix = "qxgram.settings."
    public let accountId: AccountRecordId

    public init(accountId: AccountRecordId) {
        self.accountId = accountId
    }

    private func key(_ setting: QxGramSetting) -> String {
        return "\(Self.keyPrefix)\(self.accountId.int64).\(setting.rawValue)"
    }

    public func value(_ setting: QxGramSetting) -> Bool {
        return UserDefaults.standard.bool(forKey: self.key(setting))
    }

    public func set(_ setting: QxGramSetting, value: Bool) {
        guard self.value(setting) != value else {
            return
        }
        UserDefaults.standard.set(value, forKey: self.key(setting))
        NotificationCenter.default.post(name: .qxGramSettingsDidChange, object: nil, userInfo: [
            "accountId": self.accountId.int64
        ])
    }

    public static func removeSettingsForMissingAccounts(_ accountIds: Set<AccountRecordId>) {
        let validIds = Set(accountIds.map { String($0.int64) })
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.keyPrefix) {
            let suffix = key.dropFirst(Self.keyPrefix.count)
            guard let separator = suffix.firstIndex(of: ".") else {
                continue
            }
            let accountId = String(suffix[..<separator])
            if !validIds.contains(accountId) {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
