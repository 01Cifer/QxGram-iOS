import Foundation
import Postbox

let qxGramTtlTextLabelPrefix = "🔥 TTL\n"

private func qxGramCopiedResource(_ resource: TelegramMediaResource, mediaBox: MediaBox) -> TelegramMediaResource? {
    guard mediaBox.completedResourcePath(id: resource.id) != nil else {
        return nil
    }
    let fileId = Int64.random(in: 1...Int64.max)
    let copied = LocalFileMediaResource(fileId: fileId, size: resource.size)
    mediaBox.copyResourceData(from: resource.id, to: copied.id, synchronous: true)
    return copied
}

private func qxGramCopiedRepresentation(_ representation: TelegramMediaImageRepresentation, mediaBox: MediaBox) -> TelegramMediaImageRepresentation? {
    guard let resource = qxGramCopiedResource(representation.resource, mediaBox: mediaBox) else {
        return nil
    }
    return TelegramMediaImageRepresentation(
        dimensions: representation.dimensions,
        resource: resource,
        progressiveSizes: representation.progressiveSizes,
        immediateThumbnailData: representation.immediateThumbnailData,
        hasVideo: representation.hasVideo,
        isPersonal: representation.isPersonal,
        typeHint: representation.typeHint
    )
}

private struct QxGramTtlSavedMarker: Codable {
    let saved: Bool
}

public func qxGramTtlSavedEntryId(accountId: AccountRecordId, messageId: MessageId) -> ItemCacheEntryId {
    let key = ValueBoxKey(length: 24)
    key.setInt64(0, value: accountId.int64)
    key.setInt64(8, value: messageId.peerId.toInt64())
    key.setInt32(16, value: messageId.namespace)
    key.setInt32(20, value: messageId.id)
    return ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.qxgramDeletedMessages, key: key)
}

private final class QxGramTtlGuardState {
    let lock = NSLock()
    var inFlight = Set<String>()
    var attemptsByMessage: [String: [CFAbsoluteTime]] = [:]
    var attemptsByAccount: [Int64: [CFAbsoluteTime]] = [:]
}

private let qxGramTtlGuard = QxGramTtlGuardState()

private func qxGramTtlGuardKey(accountId: AccountRecordId, messageId: MessageId) -> String {
    return "\(accountId.int64):\(messageId.peerId.toInt64()):\(messageId.namespace):\(messageId.id)"
}

public func qxGramSaveTtlLocalCopy(transaction: Transaction, mediaBox: MediaBox, accountId: AccountRecordId, message: Message) {
    guard QxGramTtlPolicy.isSaveMediaEnabled(accountId: accountId) else {
        return
    }

    let guardKey = qxGramTtlGuardKey(accountId: accountId, messageId: message.id)
    qxGramTtlGuard.lock.lock()
    if qxGramTtlGuard.inFlight.contains(guardKey) {
        qxGramTtlGuard.lock.unlock()
        Logger.shared.log("QxGram TTL", "recursion guarded: \(guardKey)")
        return
    }
    qxGramTtlGuard.inFlight.insert(guardKey)

    let now = CFAbsoluteTimeGetCurrent()
    let window: CFAbsoluteTime = 10.0
    var messageAttempts = (qxGramTtlGuard.attemptsByMessage[guardKey] ?? []).filter { now - $0 < window }
    messageAttempts.append(now)
    qxGramTtlGuard.attemptsByMessage[guardKey] = messageAttempts
    var accountAttempts = (qxGramTtlGuard.attemptsByAccount[accountId.int64] ?? []).filter { now - $0 < window }
    accountAttempts.append(now)
    qxGramTtlGuard.attemptsByAccount[accountId.int64] = accountAttempts
    let fuseTripped = messageAttempts.count > 8 || accountAttempts.count > 60
    qxGramTtlGuard.lock.unlock()

    defer {
        qxGramTtlGuard.lock.lock()
        qxGramTtlGuard.inFlight.remove(guardKey)
        qxGramTtlGuard.lock.unlock()
    }

    if fuseTripped {
        QxGramTtlPolicy.disableTtl(accountId: accountId)
        Logger.shared.log("QxGram TTL", "fuse tripped, TTL disabled for account \(accountId.int64), key \(guardKey)")
        return
    }

    let markerId = qxGramTtlSavedEntryId(accountId: accountId, messageId: message.id)
    guard transaction.retrieveItemCacheEntry(id: markerId) == nil else {
        return
    }

    let copiedMedia = qxGramCopyTtlMedia(message.media, mediaBox: mediaBox)
    guard !copiedMedia.isEmpty else {
        return
    }

    var attributes: [MessageAttribute] = []
    for attribute in message.attributes {
        if attribute is AutoclearTimeoutMessageAttribute || attribute is AutoremoveTimeoutMessageAttribute {
            continue
        }
        attributes.append(attribute)
    }

    let storeMessage = StoreMessage(
        peerId: message.id.peerId,
        namespace: Namespaces.Message.Local,
        customStableId: nil,
        globallyUniqueId: nil,
        groupingKey: nil,
        threadId: nil,
        timestamp: message.timestamp,
        flags: StoreMessageFlags(message.flags),
        tags: message.tags,
        globalTags: message.globalTags,
        localTags: message.localTags,
        forwardInfo: nil,
        authorId: message.author?.id,
        text: message.text,
        attributes: attributes,
        media: copiedMedia
    )
    let _ = transaction.addMessages([storeMessage], location: .Random)

    if let marker = CodableEntry(QxGramTtlSavedMarker(saved: true)) {
        transaction.putItemCacheEntry(id: markerId, entry: marker)
    }
    Logger.shared.log("QxGram TTL", "saved local copy for \(guardKey)")
}

public func qxGramCopyTtlMedia(_ media: [Media], mediaBox: MediaBox) -> [Media] {
    return media.compactMap { media in
        if let image = media as? TelegramMediaImage {
            let representations = image.representations.compactMap { qxGramCopiedRepresentation($0, mediaBox: mediaBox) }
            guard !representations.isEmpty else {
                return nil
            }
            return TelegramMediaImage(
                imageId: image.imageId,
                representations: representations,
                videoRepresentations: [],
                immediateThumbnailData: image.immediateThumbnailData,
                emojiMarkup: image.emojiMarkup,
                reference: image.reference,
                partialReference: image.partialReference,
                flags: image.flags,
                video: nil
            )
        } else if let file = media as? TelegramMediaFile {
            guard let resource = qxGramCopiedResource(file.resource, mediaBox: mediaBox) else {
                return nil
            }
            let previews = file.previewRepresentations.compactMap { qxGramCopiedRepresentation($0, mediaBox: mediaBox) }
            return TelegramMediaFile(
                fileId: file.fileId,
                partialReference: file.partialReference,
                resource: resource,
                previewRepresentations: previews,
                videoThumbnails: file.videoThumbnails,
                videoCover: file.videoCover,
                immediateThumbnailData: file.immediateThumbnailData,
                mimeType: file.mimeType,
                size: file.size,
                attributes: file.attributes,
                alternativeRepresentations: file.alternativeRepresentations
            )
        } else {
            return nil
        }
    }
}
