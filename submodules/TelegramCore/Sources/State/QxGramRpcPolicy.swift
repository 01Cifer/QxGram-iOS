import Foundation

/// Core-owned outgoing RPC policy. Reads the same per-account UserDefaults keys as
/// `QxGramSettings` without importing `TelegramUIPreferences` into `TelegramCore`.
public enum QxGramRpcPolicy {
    public static let keyPrefix = "qxgram.settings."

    public static func ghostKey(accountId: AccountRecordId) -> String {
        return "\(Self.keyPrefix)\(accountId.int64).ghost"
    }

    public static func isGhostEnabled(accountId: AccountRecordId) -> Bool {
        return UserDefaults.standard.bool(forKey: self.ghostKey(accountId: accountId))
    }

    /// Presence, typing and read-acknowledgement calls. Local read state is applied
    /// separately in `ApplyMaxReadIndexInteractively`, so dropping these only hides
    /// activity from the server and the other party.
    public static let ghostSuppressedFunctions: Set<String> = [
        "account.updateStatus",
        "messages.setTyping",
        "messages.setEncryptedTyping",
        "messages.readMessageContents",
        "channels.readMessageContents",
        "messages.readHistory",
        "channels.readHistory",
        "messages.readEncryptedHistory",
        "messages.readDiscussion",
        "messages.readSavedHistory",
        "messages.readReactions",
        "messages.readPollVotes"
    ]

    /// View-once media screenshot notification from ordinary chats. Secret chats are
    /// already handled earlier in `_internal_addSecretChatMessageScreenshot`.
    public static let screenshotNotificationFunctions: Set<String> = [
        "messages.sendScreenshotNotification"
    ]

    public static func shouldSuppress(accountId: AccountRecordId, functionName: String) -> Bool {
        if Self.screenshotNotificationFunctions.contains(functionName) {
            return QxGramScreenshotPolicy.isAllowed(accountId: accountId)
        }
        return Self.isGhostEnabled(accountId: accountId) && Self.ghostSuppressedFunctions.contains(functionName)
    }
}
