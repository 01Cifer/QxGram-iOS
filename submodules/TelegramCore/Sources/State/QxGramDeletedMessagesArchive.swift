import Foundation
import Postbox

public enum QxGramDeletedReason: String, Codable {
    case deletedByOther
    case deletedBySelf
    case ttl
}

public struct QxGramArchivedMessage: Codable {
    public let stableId: Int64
    public let id: MessageId
    public let timestamp: Int32
    public let flags: Int64
    public let authorData: Data?
    public var text: String
    public let mediaData: [Data]
    public let reason: String

    public init(stableId: UInt32, id: MessageId, timestamp: Int32, flags: UInt32, authorData: Data?, text: String, mediaData: [Data], reason: QxGramDeletedReason) {
        self.stableId = Int64(stableId)
        self.id = id
        self.timestamp = timestamp
        self.flags = Int64(flags)
        self.authorData = authorData
        self.text = text
        self.mediaData = mediaData
        self.reason = reason.rawValue
    }
}

public struct QxGramArchivedMessages: Codable {
    public var messages: [QxGramArchivedMessage]

    public init(messages: [QxGramArchivedMessage] = []) {
        self.messages = messages
    }
}

public func qxGramDeletedArchiveEntryId(peerId: PeerId) -> ItemCacheEntryId {
    let key = ValueBoxKey(length: 8)
    key.setInt64(0, value: peerId.toInt64())
    return ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.qxgramDeletedMessages, key: key)
}

private func qxGramEncodedPostboxObject(_ object: PostboxCoding) -> Data {
    let encoder = PostboxEncoder()
    encoder.encodeRootObject(object)
    return encoder.makeData()
}

public func qxGramDecodePeer(_ data: Data?) -> Peer? {
    guard let data = data else {
        return nil
    }
    return PostboxDecoder(buffer: MemoryBuffer(data: data)).decodeRootObject() as? Peer
}

public func qxGramDecodeMedia(_ data: [Data]) -> [Media] {
    return data.compactMap { data in
        return PostboxDecoder(buffer: MemoryBuffer(data: data)).decodeRootObject() as? Media
    }
}

public func qxGramDeletedMessageLabel(_ reason: QxGramDeletedReason, showTtl: Bool = true) -> String {
    switch reason {
        case .ttl:
            return showTtl ? "🔥 TTL" : "🗑️ Удалено"
        case .deletedByOther, .deletedBySelf:
            return "🗑️ Удалено"
    }
}

public func qxGramArchiveMessages(transaction: Transaction, messages: [Message], reason: QxGramDeletedReason) {
    guard !messages.isEmpty else {
        return
    }

    var grouped: [PeerId: [QxGramArchivedMessage]] = [:]
    for message in messages {
        let authorData: Data? = message.author.flatMap { qxGramEncodedPostboxObject($0) }
        let mediaData = message.media.map { qxGramEncodedPostboxObject($0) }
        let item = QxGramArchivedMessage(
            stableId: message.stableId,
            id: message.id,
            timestamp: message.timestamp,
            flags: message.flags.rawValue,
            authorData: authorData,
            text: message.text,
            mediaData: mediaData,
            reason: reason
        )
        grouped[message.id.peerId, default: []].append(item)
    }

    for (peerId, items) in grouped {
        let entryId = qxGramDeletedArchiveEntryId(peerId: peerId)
        var archive = transaction.retrieveItemCacheEntry(id: entryId)?.get(QxGramArchivedMessages.self) ?? QxGramArchivedMessages()
        archive.messages.append(contentsOf: items)
        if archive.messages.count > 500 {
            archive.messages.removeFirst(archive.messages.count - 500)
        }
        if let entry = CodableEntry(archive) {
            transaction.putItemCacheEntry(id: entryId, entry: entry)
        }
    }
}

public func qxGramSynthesizeArchivedMessage(_ item: QxGramArchivedMessage, showTtl: Bool = true) -> Message {
    let reason = QxGramDeletedReason(rawValue: item.reason) ?? .deletedByOther
    let label = qxGramDeletedMessageLabel(reason, showTtl: showTtl)
    let text = item.text.isEmpty ? label : "\(label)\n\(item.text)"
    return Message(
        stableId: UInt32(truncatingIfNeeded: item.stableId),
        stableVersion: 0,
        id: item.id,
        globallyUniqueId: nil,
        groupingKey: nil,
        groupInfo: nil,
        threadId: nil,
        timestamp: item.timestamp,
        flags: MessageFlags(rawValue: UInt32(truncatingIfNeeded: item.flags)),
        tags: [],
        globalTags: [],
        localTags: [],
        customTags: [],
        forwardInfo: nil,
        author: qxGramDecodePeer(item.authorData),
        text: text,
        attributes: [],
        media: qxGramDecodeMedia(item.mediaData),
        peers: SimpleDictionary(),
        associatedMessages: SimpleDictionary(),
        associatedMessageIds: [],
        associatedMedia: [:],
        associatedThreadInfo: nil,
        associatedStories: [:]
    )
}
