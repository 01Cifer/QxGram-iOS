import Foundation
import Postbox

private let qxGramTtlRepairMigrationKeyPrefix = "qxgram.migration.ttlRepair.v1."

public func qxGramRunTtlRepairMigration(accountId: AccountRecordId, transaction: Transaction) {
    let migrationKey = "\(qxGramTtlRepairMigrationKeyPrefix)\(accountId.int64)"
    let forced = QxGramLaunchSafety.isEmergencyMode()
    guard forced || !UserDefaults.standard.bool(forKey: migrationKey) else {
        return
    }

    var removed = 0
    for peerId in transaction.chatListGetAllPeerIds() {
        let entryId = qxGramDeletedArchiveEntryId(peerId: peerId)
        guard let archive = transaction.retrieveItemCacheEntry(id: entryId)?.get(QxGramArchivedMessages.self) else {
            continue
        }

        var cleaned: [QxGramArchivedMessage] = []
        var seenIds = Set<String>()
        var seenFingerprints = Set<String>()
        var changed = false

        for item in archive.messages {
            let idKey = "\(item.id.peerId.toInt64()):\(item.id.namespace):\(item.id.id)"
            let fingerprint = "\(idKey):\(item.timestamp):\(item.text)"
            let valid = qxGramArchivedMessageIsValid(item) && seenIds.insert(idKey).inserted && seenFingerprints.insert(fingerprint).inserted
            if valid {
                cleaned.append(item)
            } else {
                changed = true
                removed += 1
                Logger.shared.log("QxGram archive", "repair dropped invalid entry \(idKey) for account \(accountId.int64)")
            }
        }

        if changed {
            var updated = archive
            updated.messages = cleaned
            if let entry = CodableEntry(updated) {
                transaction.putItemCacheEntry(id: entryId, entry: entry)
            }
        }
    }

    UserDefaults.standard.set(true, forKey: migrationKey)
    Logger.shared.log("QxGram archive", "repair removed \(removed) invalid entries for account \(accountId.int64)")
}
