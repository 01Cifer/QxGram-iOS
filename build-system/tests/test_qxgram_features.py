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
        self.assertIn("let qxGramSettings = QxGramSettings(accountId: context.account.id)", entries_text)
        self.assertIn("qxGramSettings.value(.showDeletedMessages)", entries_text)
        self.assertIn("archivedMessages = data.messages.map { qxGramSynthesizeArchivedMessage($0, showTtl: qxGramSettings.value(.showTtl)) }", entries_text)
        self.assertIn("if !archivedMessages.isEmpty", entries_text)
        self.assertIn("entries.append(.MessageEntry(message, presentationData", entries_text)

    def test_settings_notice_no_longer_claims_deleted_messages_missing(self):
        text = source("submodules/SettingsUI/Sources/QxGramSettingsController.swift")
        self.assertIn("Удалённые сообщения архивируются", text)
        self.assertNotIn("функции Ghost, удалённых сообщений, TTL и скриншотов пока не реализованы", text)


class QxGramTtlMediaTests(unittest.TestCase):
    def test_show_ttl_setting_exists_and_is_wired(self):
        preferences = source("submodules/TelegramUIPreferences/Sources/QxGramSettings.swift")
        self.assertIn("case showTtl", preferences)

        controller = source("submodules/SettingsUI/Sources/QxGramSettingsController.swift")
        self.assertIn("case showTtl(Bool)", controller)
        self.assertIn('title = "Показывать TTL"', controller)
        self.assertIn("setting = .showTtl", controller)
        self.assertIn(".showTtl(settings.value(.showTtl))", controller)

    def test_core_policy_uses_same_user_defaults_keys(self):
        policy = source("submodules/TelegramCore/Sources/State/QxGramTtlPolicy.swift")
        self.assertIn('static let keyPrefix = "qxgram.settings."', policy)
        self.assertIn('setting: "saveTtlMedia"', policy)
        self.assertIn('setting: "showTtl"', policy)
        self.assertNotIn("import TelegramUIPreferences", policy)

        preferences = source("submodules/TelegramUIPreferences/Sources/QxGramSettings.swift")
        self.assertIn('private static let keyPrefix = "qxgram.settings."', preferences)
        self.assertIn("case saveTtlMedia", preferences)
        self.assertIn("case showTtl", preferences)

    def test_ttl_copy_happens_before_autoremove_delete(self):
        copy_text = source("submodules/TelegramCore/Sources/State/QxGramTtlMediaCopy.swift")
        self.assertIn("public func qxGramSaveTtlLocalCopy(", copy_text)
        self.assertIn("QxGramTtlPolicy.isSaveMediaEnabled(accountId: accountId)", copy_text)
        self.assertIn("qxGramCopyTtlMedia(message.media, mediaBox: mediaBox)", copy_text)
        self.assertIn("mediaBox.copyResourceData(from: resource.id, to: copied.id, synchronous: true)", copy_text)
        self.assertIn("LocalFileMediaResource(fileId: fileId, size: resource.size)", copy_text)
        self.assertIn('QxGramTtlPolicy.isShowTtlEnabled(accountId: accountId) ? "🔥 TTL\\n" : ""', copy_text)
        self.assertIn("transaction.addMessages([storeMessage], location: .Random)", copy_text)

        autoremove = source("submodules/TelegramCore/Sources/State/ManagedAutoremoveMessageOperations.swift")
        self.assertIn("accountId: AccountRecordId", autoremove)
        archive_index = autoremove.index("qxGramArchiveMessages(transaction: transaction, messages: [message], reason: .ttl)")
        copy_index = autoremove.index("qxGramSaveTtlLocalCopy(transaction: transaction, mediaBox: postbox.mediaBox, accountId: accountId, message: message)")
        delete_index = autoremove.index("_internal_deleteMessages(transaction: transaction, mediaBox: postbox.mediaBox, ids: [entry.messageId])")
        self.assertLess(archive_index, copy_index)
        self.assertLess(copy_index, delete_index)

        account = source("submodules/TelegramCore/Sources/Account/Account.swift")
        self.assertEqual(account.count("managedAutoremoveMessageOperations(network: self.network, postbox: self.postbox, accountId: self.id"), 2)

    def test_ttl_label_respects_toggle(self):
        text = source("submodules/TelegramCore/Sources/State/QxGramDeletedMessagesArchive.swift")
        self.assertIn("public func qxGramDeletedMessageLabel(_ reason: QxGramDeletedReason, showTtl: Bool = true)", text)
        self.assertIn('return showTtl ? "🔥 TTL" : "🗑️ Удалено"', text)
        self.assertIn("qxGramSynthesizeArchivedMessage($0, showTtl: qxGramSettings.value(.showTtl))", source("submodules/TelegramUI/Sources/ChatHistoryEntriesForView.swift"))


if __name__ == "__main__":
    unittest.main()
