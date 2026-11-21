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
        self.assertIn("archivedMessages = data.messages.compactMap { item in", entries_text)
        self.assertIn("guard qxGramArchivedMessageIsValid(item) else", entries_text)
        self.assertIn("if !archivedMessages.isEmpty", entries_text)
        self.assertIn("entries.append(.MessageEntry(message, presentationData", entries_text)

    def test_settings_notice_no_longer_claims_deleted_messages_missing(self):
        text = source("submodules/SettingsUI/Sources/QxGramSettingsController.swift")
        self.assertIn("архив удалённых", text)
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
        self.assertIn("text: message.text,", copy_text)
        self.assertIn("if attribute is AutoclearTimeoutMessageAttribute || attribute is AutoremoveTimeoutMessageAttribute", copy_text)
        self.assertIn("public func qxGramTtlSavedEntryId(accountId: AccountRecordId, messageId: MessageId)", copy_text)
        self.assertNotIn("let label =", copy_text)
        self.assertNotIn('text: "\\(label)\\(message.text)"', copy_text)
        self.assertIn("let _ = transaction.addMessages([storeMessage], location: .Random)", copy_text)

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
        self.assertIn("qxGramArchivedMessageIsValid(item)", source("submodules/TelegramUI/Sources/ChatHistoryEntriesForView.swift"))
        self.assertIn("attributes: [QxGramStatusBadgeMessageAttribute(label: label)]", text)
        self.assertNotIn("let text = item.text.isEmpty ? label", text)


class QxGramStatusBadgeTests(unittest.TestCase):
    def test_badge_attribute_is_codec_and_registered(self):
        attribute = source("submodules/TelegramCore/Sources/State/QxGramStatusBadgeMessageAttribute.swift")
        self.assertIn("public class QxGramStatusBadgeMessageAttribute: MessageAttribute", attribute)
        self.assertIn('decoder.decodeStringForKey("l", orElse: "")', attribute)
        self.assertIn('encoder.encodeString(self.label, forKey: "l")', attribute)

        manager = source("submodules/TelegramCore/Sources/Account/AccountManager.swift")
        self.assertIn("declareEncodable(QxGramStatusBadgeMessageAttribute.self", manager)

    def test_badge_is_one_line_in_date_status_string(self):
        status = source("submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode/Sources/StringForMessageTimestampStatus.swift")
        self.assertIn("if let badge = attribute as? QxGramStatusBadgeMessageAttribute", status)
        self.assertIn("let label = badge.label.trimmingCharacters(in: .whitespacesAndNewlines)", status)
        self.assertIn('dateText = "\\(dateText) \\(String(label.prefix(64)))"', status)
        self.assertIn("break", status)

        copy_text = source("submodules/TelegramCore/Sources/State/QxGramTtlMediaCopy.swift")
        self.assertIn("attributes.append(QxGramStatusBadgeMessageAttribute(label: qxGramDeletedMessageLabel(.ttl)))", copy_text)


class QxGramScreenshotTests(unittest.TestCase):
    def test_policy_key_matches_settings_and_has_no_ui_dependency(self):
        policy = source("submodules/TelegramCore/Sources/State/QxGramScreenshotPolicy.swift")
        self.assertIn('static let keyPrefix = "qxgram.settings."', policy)
        self.assertIn('\\(accountId.int64).allowScreenshots', policy)
        self.assertIn("public static func shouldProtect(isSecret: Bool, screenshotsAllowed: Bool) -> Bool", policy)
        self.assertIn("return isSecret && !screenshotsAllowed", policy)
        self.assertNotIn("import TelegramUIPreferences", policy)

        preferences = source("submodules/TelegramUIPreferences/Sources/QxGramSettings.swift")
        self.assertIn('private static let keyPrefix = "qxgram.settings."', preferences)
        self.assertIn("case allowScreenshots", preferences)

    def test_secret_chat_screenshot_notification_is_suppressed(self):
        text = source("submodules/TelegramCore/Sources/SecretChats/SetSecretChatMessageAutoremoveTimeoutInteractively.swift")
        self.assertIn("func _internal_addSecretChatMessageScreenshot(account: Account, peerId: PeerId)", text)
        self.assertIn("guard !QxGramScreenshotPolicy.isAllowed(accountId: account.id) else", text)
        self.assertIn("return .complete()", text)

        controller = source("submodules/TelegramUI/Sources/ChatController.swift")
        self.assertIn("if peerId.namespace == Namespaces.Peer.SecretChat && !QxGramScreenshotPolicy.isAllowed(accountId: self.context.account.id)", controller)

    def test_local_protection_is_gated_everywhere(self):
        checks = {
            "submodules/TelegramUI/Sources/ChatControllerNode.swift": [
                "QxGramScreenshotPolicy.shouldProtect(isSecret: chatLocation.peerId?.namespace",
                "let effectiveIsSecret = QxGramScreenshotPolicy.shouldProtect(isSecret: isSecret",
                "screenshotsAllowed: QxGramScreenshotPolicy.isAllowed(accountId: strongSelf.context.account.id)",
                "self.qxGramScreenshotSettingsObserver = NotificationCenter.default.addObserver(forName: .qxGramSettingsDidChange",
            ],
            "submodules/TelegramUI/Sources/ChatController.swift": [
                "disableScreenshots: QxGramScreenshotPolicy.shouldProtect(isSecret: isSecret, screenshotsAllowed: screenshotsAllowed)",
            ],
            "submodules/TelegramUI/Sources/Chat/ChatControllerOpenMessageContextMenu.swift": [
                "disableScreenshots: QxGramScreenshotPolicy.shouldProtect(isSecret: isSecret, screenshotsAllowed: screenshotsAllowed)",
            ],
            "submodules/TelegramUI/Components/Chat/ChatMessageInteractiveMediaNode/Sources/ChatMessageInteractiveMediaNode.swift": [
                "captureProtected: QxGramScreenshotPolicy.shouldProtect(isSecret: associatedData.isCopyProtectionEnabled",
                "strongSelf.imageNode.captureProtected = QxGramScreenshotPolicy.shouldProtect(isSecret: associatedData.isCopyProtectionEnabled",
            ],
            "submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift": [
                "return QxGramScreenshotPolicy.shouldProtect(isSecret: item.associatedData.isCopyProtectionEnabled || item.message.isCopyProtected(), screenshotsAllowed: QxGramScreenshotPolicy.isAllowed(accountId: item.context.account.id))",
            ],
        }
        for relative_path, needles in checks.items():
            text = source(relative_path)
            for needle in needles:
                with self.subTest(path=relative_path, needle=needle):
                    self.assertIn(needle, text)

    def test_settings_notice_no_longer_claims_screenshots_missing(self):
        text = source("submodules/SettingsUI/Sources/QxGramSettingsController.swift")
        self.assertIn("скриншоты", text)
        self.assertNotIn("скриншоты ещё не реализованы", text)


class QxGramGhostTests(unittest.TestCase):
    def test_ghost_policy_uses_same_user_defaults_key(self):
        policy = source("submodules/TelegramCore/Sources/State/QxGramRpcPolicy.swift")
        self.assertIn('static let keyPrefix = "qxgram.settings."', policy)
        self.assertIn('\\(accountId.int64).ghost', policy)
        self.assertIn("public static func isGhostEnabled(accountId: AccountRecordId) -> Bool", policy)
        self.assertNotIn("import TelegramUIPreferences", policy)

        preferences = source("submodules/TelegramUIPreferences/Sources/QxGramSettings.swift")
        self.assertIn("case ghost", preferences)

    def test_all_ghost_rpc_names_are_covered(self):
        policy = source("submodules/TelegramCore/Sources/State/QxGramRpcPolicy.swift")
        expected = [
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
            "messages.readPollVotes",
        ]
        for name in expected:
            with self.subTest(name=name):
                self.assertIn('"{}"'.format(name), policy)
        self.assertIn("return Self.isGhostEnabled(accountId: accountId) && Self.ghostSuppressedFunctions.contains(functionName)", policy)
        self.assertIn("return QxGramScreenshotPolicy.isAllowed(accountId: accountId)", policy)

    def test_network_filters_both_request_entry_points(self):
        text = source("submodules/TelegramCore/Sources/Network/Network.swift")
        self.assertIn("public let accountId: AccountRecordId", text)
        self.assertIn("self.accountId = accountId", text)
        self.assertIn("fileprivate init(accountId: AccountRecordId, queue: Queue", text)
        self.assertIn("let network = Network(accountId: accountId, queue: queue", text)
        self.assertEqual(text.count("if QxGramRpcPolicy.shouldSuppress(accountId: self.accountId, functionName: data.0.name)"), 2)
        self.assertEqual(text.count("return .complete()"), 2)

    def test_secret_chat_read_receipts_are_gated(self):
        text = source("submodules/TelegramCore/Sources/TelegramEngine/Messages/MarkMessageContentAsConsumedInteractively.swift")
        self.assertIn("func _internal_markMessageContentAsConsumedInteractively(postbox: Postbox, accountId: AccountRecordId, messageId: MessageId)", text)
        self.assertIn("let ghostEnabled = QxGramRpcPolicy.isGhostEnabled(accountId: accountId)", text)
        self.assertEqual(text.count("if !ghostEnabled, let"), 3)
        engine = source("submodules/TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift")
        self.assertIn("_internal_markMessageContentAsConsumedInteractively(postbox: self.account.postbox, accountId: self.account.id, messageId: messageId)", engine)

    def test_local_read_still_applies_before_rpc(self):
        text = source("submodules/TelegramCore/Sources/TelegramEngine/Messages/ApplyMaxReadIndexInteractively.swift")
        apply_index = text.index("let messageIds = transaction.applyInteractiveReadMaxIndex(index)")
        self.assertGreater(len(text[apply_index:]), 0)
        self.assertIn("stateManager.notifyAppliedIncomingReadMessages([index.id])", text)

    def test_settings_notice_is_final(self):
        text = source("submodules/SettingsUI/Sources/QxGramSettingsController.swift")
        self.assertIn("Все функции QxGram активны", text)
        self.assertNotIn("Ghost ещё не реализован", text)

    def test_ghost_button_is_in_chat_list_header_button_row(self):
        text = source("submodules/ChatListUI/Sources/ChatListController.swift")
        self.assertIn("var rightButtons = primaryContext.rightButtons", text)
        self.assertIn('id: "qxgram-ghost"', text)
        self.assertIn('.emoji(title: "👻", isActive: settings.value(.ghost))', text)
        self.assertIn("settings.set(.ghost, value: !settings.value(.ghost))", text)
        self.assertIn("rightButtons: rightButtons", text)
        self.assertNotIn("additionalLeftButtons: additionalLeftButtons", text)


class QxGramTtlLoopSafetyTests(unittest.TestCase):
    def test_copy_is_idempotent_and_does_not_reschedule_itself(self):
        copy_text = source("submodules/TelegramCore/Sources/State/QxGramTtlMediaCopy.swift")
        self.assertIn("let key = ValueBoxKey(length: 24)", copy_text)
        self.assertIn("key.setInt64(0, value: accountId.int64)", copy_text)
        self.assertIn("key.setInt32(16, value: messageId.namespace)", copy_text)
        self.assertIn("transaction.retrieveItemCacheEntry(id: markerId) == nil", copy_text)
        self.assertIn("transaction.putItemCacheEntry(id: markerId, entry: marker)", copy_text)
        self.assertIn("if qxGramTtlGuard.inFlight.contains(guardKey)", copy_text)
        self.assertIn("qxGramTtlGuard.inFlight.insert(guardKey)", copy_text)
        self.assertIn("qxGramTtlGuard.inFlight.remove(guardKey)", copy_text)

    def test_fuse_trips_and_disables_ttl(self):
        policy = source("submodules/TelegramCore/Sources/State/QxGramTtlPolicy.swift")
        self.assertIn('private static let fuseKeySuffix = "ttlFuseTripped"', policy)
        self.assertIn("public static func isTtlDisabled(accountId: AccountRecordId) -> Bool", policy)
        self.assertIn("public static func disableTtl(accountId: AccountRecordId)", policy)
        self.assertIn('setting: "saveTtlMedia"', policy)
        self.assertIn('setting: "showTtl"', policy)
        self.assertIn("guard !Self.isTtlDisabled(accountId: accountId) else", policy)

        copy_text = source("submodules/TelegramCore/Sources/State/QxGramTtlMediaCopy.swift")
        self.assertIn("let fuseTripped = messageAttempts.count > 8 || accountAttempts.count > 60", copy_text)
        self.assertIn("QxGramTtlPolicy.disableTtl(accountId: accountId)", copy_text)
        self.assertIn('Logger.shared.log("QxGram TTL", "fuse tripped', copy_text)

    def test_migration_cleans_spam_and_restores_previews(self):
        migration = source("submodules/TelegramCore/Sources/State/QxGramTtlLoopMigration.swift")
        self.assertIn("public func qxGramRunTtlLoopMigration(accountId: AccountRecordId, transaction: Transaction)", migration)
        self.assertIn("transaction.chatListGetAllPeerIds()", migration)
        self.assertIn("message.text.hasPrefix(qxGramTtlTextLabelPrefix)", migration)
        self.assertIn("transaction.deleteMessages(spamIds, forEachMedia: nil)", migration)
        self.assertIn("transaction.removeItemCacheEntry(id: qxGramTtlSavedEntryId(accountId: accountId, messageId: id))", migration)
        self.assertIn("qxGramStrippedTtlText(item.text)", migration)
        self.assertIn("UserDefaults.standard.set(true, forKey: migrationKey)", migration)

        account = source("submodules/TelegramCore/Sources/Account/Account.swift")
        self.assertIn("qxGramRunTtlLoopMigration(accountId: migrationAccountId, transaction: transaction)", account)
        migration_index = account.index("qxGramRunTtlLoopMigration(accountId: migrationAccountId")
        autoremove_index = account.index("managedAutoremoveMessageOperations(network: self.network, postbox: self.postbox, accountId: self.id, isRemove: true)")
        self.assertLess(migration_index, autoremove_index)


class QxGramTtlCrashLoopTests(unittest.TestCase):
    def test_expired_media_decoder_cannot_trap(self):
        text = source("submodules/TelegramCore/Sources/SyncCore/SyncCore_TelegramMediaExpiredContent.swift")
        self.assertNotIn("TelegramMediaExpiredContentData(rawValue: decoder.decodeInt32ForKey(\"d\", orElse: 0))!", text)
        self.assertIn("let raw = decoder.decodeInt32ForKey(\"d\", orElse: TelegramMediaExpiredContentData.image.rawValue)", text)
        self.assertIn("TelegramMediaExpiredContentData(rawValue: raw) ?? .image", text)

    def test_archive_decode_logs_and_drops_bad_blob(self):
        text = source("submodules/TelegramCore/Sources/State/QxGramDeletedMessagesArchive.swift")
        self.assertIn("public func qxGramDecodeMediaChecking(_ data: [Data]) -> (media: [Media], invalid: Int)", text)
        self.assertIn('Logger.shared.log("QxGram archive", "dropping undecodable media blob")', text)
        self.assertIn("public func qxGramArchivedMessageIsValid(_ item: QxGramArchivedMessage) -> Bool", text)
        self.assertIn("guard QxGramDeletedReason(rawValue: item.reason) != nil else", text)
        self.assertIn("qxGramDecodeMediaChecking(item.mediaData).invalid == 0", text)
        self.assertIn("guard !messages.isEmpty, !QxGramTtlPolicy.isEmergencyDisabled() else", text)

    def test_startup_repair_migration_cleans_archive(self):
        migration = source("submodules/TelegramCore/Sources/State/QxGramTtlRepairMigration.swift")
        self.assertIn("public func qxGramRunTtlRepairMigration(accountId: AccountRecordId, transaction: Transaction)", migration)
        self.assertIn("let forced = QxGramLaunchSafety.isEmergencyMode()", migration)
        self.assertIn("transaction.retrieveItemCacheEntry(id: entryId)", migration)
        self.assertIn("seenIds.insert(idKey).inserted", migration)
        self.assertIn("seenFingerprints.insert(fingerprint).inserted", migration)
        self.assertIn("transaction.putItemCacheEntry(id: entryId, entry: entry)", migration)
        account = source("submodules/TelegramCore/Sources/Account/Account.swift")
        self.assertIn("qxGramRunTtlRepairMigration(accountId: migrationAccountId, transaction: transaction)", account)

    def test_local_copy_has_no_stale_cloud_reference_and_open_guard(self):
        copy_text = source("submodules/TelegramCore/Sources/State/QxGramTtlMediaCopy.swift")
        self.assertIn("public func qxGramMessageIsTtl(_ message: Message) -> Bool", copy_text)
        self.assertIn("public func qxGramMessageHasLocalMediaCopy(_ message: Message) -> Bool", copy_text)
        self.assertIn("public func qxGramTtlMediaIsUnavailable(_ message: Message) -> Bool", copy_text)
        self.assertIn("representation.resource is LocalFileMediaResource", copy_text)
        self.assertIn("file.resource is LocalFileMediaResource", copy_text)
        self.assertIn("reference: nil,", copy_text)
        self.assertIn("partialReference: nil,", copy_text)
        opened = source("submodules/TelegramUI/Sources/OpenChatMessage.swift")
        self.assertIn("if qxGramMessageIsTtl(params.message) && qxGramTtlMediaIsUnavailable(params.message) && !qxGramMessageHasLocalMediaCopy(params.message)", opened)
        self.assertIn("Медиа уже недоступно: локальная копия не была сохранена.", opened)

    def test_launch_safety_emergency_brake(self):
        safety = source("submodules/TelegramCore/Sources/State/QxGramLaunchSafety.swift")
        self.assertIn('private static let emergencyKey = "qxgram.emergency.ttlDisabled"', safety)
        self.assertIn('private static let noticeKey = "qxgram.emergency.ttlNoticePending"', safety)
        self.assertIn("public static func recordLaunchAttempt()", safety)
        self.assertIn("if failures >= 2", safety)
        self.assertIn("public static func markLaunchStable()", safety)
        self.assertIn("public static func consumePendingNotice() -> Bool", safety)
        app = source("submodules/TelegramUI/Sources/AppDelegate.swift")
        self.assertIn("QxGramLaunchSafety.recordLaunchAttempt()", app)
        self.assertIn("QxGramLaunchSafety.markLaunchStable()", app)
        self.assertIn("QxGramLaunchSafety.consumePendingNotice()", app)
        policy = source("submodules/TelegramCore/Sources/State/QxGramTtlPolicy.swift")
        self.assertIn("return Self.isEmergencyDisabled() || UserDefaults.standard.bool(forKey: Self.fuseKey(accountId: accountId))", policy)
        entries = source("submodules/TelegramUI/Sources/ChatHistoryEntriesForView.swift")
        self.assertIn("!QxGramTtlPolicy.isEmergencyDisabled()", entries)


if __name__ == "__main__":
    unittest.main()
