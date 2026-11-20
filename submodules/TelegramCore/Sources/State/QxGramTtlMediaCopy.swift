import Foundation
import Postbox

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

public func qxGramTtlSavedEntryId(messageId: MessageId) -> ItemCacheEntryId {
    let key = ValueBoxKey(length: 16)
    key.setInt64(0, value: messageId.peerId.toInt64())
    key.setInt32(8, value: messageId.namespace)
    key.setInt32(12, value: messageId.id)
    return ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.qxgramDeletedMessages, key: key)
}

public func qxGramSaveTtlLocalCopy(transaction: Transaction, mediaBox: MediaBox, accountId: AccountRecordId, message: Message) {
    guard QxGramTtlPolicy.isSaveMediaEnabled(accountId: accountId) else {
        return
    }
    let markerId = qxGramTtlSavedEntryId(messageId: message.id)
    guard transaction.retrieveItemCacheEntry(id: markerId) == nil else {
        return
    }

    let copiedMedia = qxGramCopyTtlMedia(message.media, mediaBox: mediaBox)
    guard !copiedMedia.isEmpty else {
        return
    }

    let label = QxGramTtlPolicy.isShowTtlEnabled(accountId: accountId) ? "🔥 TTL\n" : ""
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
        text: "\(label)\(message.text)",
        attributes: message.attributes,
        media: copiedMedia
    )
    let _ = transaction.addMessages([storeMessage], location: .Random)

    if let marker = CodableEntry(QxGramTtlSavedMarker(saved: true)) {
        transaction.putItemCacheEntry(id: markerId, entry: marker)
    }
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
