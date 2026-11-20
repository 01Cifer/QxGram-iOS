import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


def source(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class QxGramDeletedMessagesTests(unittest.TestCase):
    def test_archive_helper_is_self_contained_in_core(self):
        text = source("submodules/TelegramCore/Sources/State/QxGramDeletedMessagesArchive.swift")
        self.assertIn("public enum QxGramDeletedReason: String, Codable", text)
        self.assertIn("public struct QxGramArchivedMessages: Codable", text)
        self.assertIn("public func qxGramArchiveMessages(", text)
        self.assertIn('return "🗑️ Удалено"', text)
        self.assertIn("PostboxEncoder()", text)
        self.assertIn("transaction.putItemCacheEntry(id: entryId, entry: entry)", text)
        self.assertNotIn("import TelegramUIPreferences", text)

    def test_cache_collection_id_is_new(self):
        text = source("submodules/TelegramCore/Sources/SyncCore/SyncCore_Namespaces.swift")
        self.assertIn("public static let qxgramDeletedMessages: Int8 = 60", text)
        self.assertNotIn("public static let cachedWalletUserAddresses: Int8 = 60", text)

    def test_all_deletion_paths_archive_before_delete(self):
        checks = {
            "submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift": [
                "qxGramArchiveMessages(transaction: transaction, messages: transaction.messageIdsForGlobalIds(ids)",
                "qxGramArchiveMessages(transaction: transaction, messages: ids.compactMap",
                "qxGramArchiveMessages(transaction: transaction, messages: archivedRangeMessages",
            ],
            "submodules/TelegramCore/Sources/State/ProcessSecretChatIncomingDecryptedOperations.swift": [
                "qxGramArchiveMessages(transaction: transaction, messages: filteredMessageIds.compactMap",
            ],
            "submodules/TelegramCore/Sources/State/ManagedAutoremoveMessageOperations.swift": [
                "qxGramArchiveMessages(transaction: transaction, messages: [message], reason: .ttl)",
            ],
        }
        for relative_path, needles in checks.items():
            text = source(relative_path)
            for needle in needles:
                with self.subTest(path=relative_path, needle=needle):
                    self.assertIn(needle, text)

    def test_chat_history_requests_and_renders_archive(self):
        list_text = source("submodules/TelegramUI/Sources/ChatHistoryListNode.swift")
        self.assertIn("additionalData.append(.cacheEntry(qxGramDeletedArchiveEntryId(peerId: peerId)))", list_text)

        entries_text = source("submodules/TelegramUI/Sources/ChatHistoryEntriesForView.swift")
        self.assertIn("import TelegramUIPreferences", entries_text)
        self.assertIn("id == qxGramDeletedArchiveEntryId(peerId: peerId)", entries_text)
        self.assertIn("QxGramSettings(accountId: context.account.id).value(.showDeletedMessages)", entries_text)
        self.assertIn("archivedMessages = data.messages.map { qxGramSynthesizeArchivedMessage($0) }", entries_text)
        self.assertIn("if !archivedMessages.isEmpty", entries_text)
        self.assertIn("entries.append(.MessageEntry(message, presentationData", entries_text)

    def test_settings_notice_no_longer_claims_deleted_messages_missing(self):
        text = source("submodules/SettingsUI/Sources/QxGramSettingsController.swift")
        self.assertIn("Удалённые сообщения архивируются", text)
        self.assertNotIn("функции Ghost, удалённых сообщений, TTL и скриншотов пока не реализованы", text)


if __name__ == "__main__":
    unittest.main()
