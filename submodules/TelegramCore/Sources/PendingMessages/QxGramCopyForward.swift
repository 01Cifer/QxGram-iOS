import Foundation
import Postbox

public func qxGramCanCopyForwardAsNew(_ message: Message) -> Bool {
    for media in message.media {
        if media is TelegramMediaAction || media is TelegramMediaExpiredContent || media is TelegramMediaPoll || media is TelegramMediaTodo || media is TelegramMediaPaidContent {
            return false
        }
    }
    return true
}

public func qxGramCopyForwardEnqueueMessages(_ messages: [Message], hidesCaptions: Bool = false) -> [EnqueueMessage] {
    let sorted = messages.sorted { $0.id < $1.id }
    var generatedKeys: [Int64: Int64] = [:]

    return sorted.indices.map { index in
        let message = sorted[index]
        let useStandalone = message.id.peerId.namespace == Namespaces.Peer.SecretChat || message.id.namespace == Namespaces.Message.Local || message.id.namespace == Namespaces.Message.EphemeralLocal
        var mediaReference: AnyMediaReference?
        if let media = message.effectiveMedia.first {
            let base: AnyMediaReference = useStandalone
                ? .standalone(media: media)
                : .message(message: MessageReference(message), media: media)
            let augmented = augmentMediaWithReference(base)
            mediaReference = useStandalone
                ? .standalone(media: augmented)
                : .message(message: MessageReference(message), media: augmented)
        }
        let isLastInAlbum: Bool
        if let groupingKey = message.groupingKey {
            isLastInAlbum = index + 1 == sorted.count || sorted[index + 1].groupingKey != groupingKey
        } else {
            isLastInAlbum = true
        }
        let hidesCaption = (hidesCaptions && mediaReference != nil) || !isLastInAlbum
        let text = hidesCaption ? "" : message.text
        let attributes = forwardCopyRequestedAttributes(
            sourceAttributes: message.attributes,
            forwardAttributes: [],
            hidesCaption: hidesCaption
        )

        return .message(
            text: text,
            attributes: attributes,
            inlineStickers: [:],
            mediaReference: mediaReference,
            threadId: nil,
            replyToMessageId: nil,
            replyToStoryId: nil,
            localGroupingKey: forwardGroupingKey(grouping: .auto, sourceGroupingKey: message.groupingKey, generatedKeys: &generatedKeys),
            correlationId: nil,
            bubbleUpEmojiOrStickersets: []
        )
    }
}
