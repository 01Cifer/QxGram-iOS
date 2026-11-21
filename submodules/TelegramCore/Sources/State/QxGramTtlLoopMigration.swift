import Foundation
import Postbox

private let qxGramTtlMigrationKeyPrefix = "qxgram.migration.ttlLoop.v1."

private func qxGramStrippedTtlText(_ text: String) -> String {
    var result = text
    while result.hasPrefix(qxGramTtlTextLabelPrefix) {
        result.removeFirst(qxGramTtlTextLabelPrefix.count)
    }
    return result
}

public func qxGramRunTtlLoopMigration(accountId: AccountRecordId, transaction: Transaction) {
    let migrationKey = "\(qxGramTtlMigrationKeyPrefix)\(accountId.int64)"
    guard !UserDefaults.standard.bool(forKey: migrationKey) else {
        return
    }

    var spamIds: [MessageId] = []
    var removedDuplicates = 0

    for peerId in transaction.chatListGetAllPeerIds() {
        let localMessages = transaction.getMessages(
            peerId: peerId,
            namespace: Namespaces.Message.Local,
            from: MessageIndex.upperBound(peerId: peerId, namespace: Namespaces.Message.Local),
            includeFrom: true,
            to: MessageIndex.lowerBound(peerId: peerId, namespace: Namespaces.Message.Local),
            limit: 2000
        )
        for message in localMessages where message.text.hasPrefix(qxGramTtlTextLabelPrefix) {
            spamIds.append(message.id)
        }

        let archiveId = qxGramDeletedArchiveEntryId(peerId: peerId)
        guard let archive = transaction.retrieveItemCacheEntry(id: archiveId)?.get(QxGramArchivedMessages.self) else {
            continue
        }
        var cleaned: [QxGramArchivedMessage] = []
        var seen = Set<String>()
        var changed = false
        for item in archive.messages {
            let text = qxGramStrippedTtlText(item.text)
            let fingerprint = "\(item.timestamp)|\(text)|\(item.authorData?.base64EncodedString() ?? "")"
            guard seen.insert(fingerprint).inserted else {
                changed = true
                continue
            }
            var updated = item
            if updated.text != text {
                updated.text = text
                changed = true
            }
            cleaned.append(updated)
        }
        if changed {
            var updatedArchive = archive
            updatedArchive.messages = cleaned
            if let entry = CodableEntry(updatedArchive) {
                transaction.putItemCacheEntry(id: archiveId, entry: entry)
            }
            removedDuplicates += archive.messages.count - cleaned.count
        }
    }

    for id in spamIds {
        transaction.removeItemCacheEntry(id: qxGramTtlSavedEntryId(accountId: accountId, messageId: id))
    }
    if !spamIds.isEmpty {
        transaction.deleteMessages(spamIds, forEachMedia: nil)
    }
    UserDefaults.standard.set(true, forKey: migrationKey)
    Logger.shared.log("QxGram TTL", "migration removed \(spamIds.count) spam copies and \(removedDuplicates) duplicate archive entries")
}
