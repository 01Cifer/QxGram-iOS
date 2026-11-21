import Foundation
import Postbox

public class QxGramStatusBadgeMessageAttribute: MessageAttribute {
    public let label: String

    public init(label: String) {
        self.label = label
    }

    required public init(decoder: PostboxDecoder) {
        self.label = decoder.decodeStringForKey("l", orElse: "")
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self.label, forKey: "l")
    }
}
