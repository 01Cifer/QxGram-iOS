import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import DeviceAccess

public enum QxGramMediaSaveResult {
    case saved
    case denied
}

/// Requests Photo Library access explicitly so callers can show a clear message when it is denied.
public func qxGramSaveToCameraRollWithPermission(
    context: AccountContext,
    userLocation: MediaResourceUserLocation,
    mediaReference: AnyMediaReference,
    video: AnyMediaReference? = nil,
    present: @escaping (ViewController, Any?) -> Void
) -> Signal<QxGramMediaSaveResult, NoError> {
    return Signal { subscriber in
        var innerDisposable: Disposable?
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        DeviceAccess.authorizeAccess(to: .mediaLibrary(.save), presentationData: presentationData, present: { c, a in
            present(c, a)
        }, openSettings: context.sharedContext.applicationBindings.openSettings, { authorized in
            if !authorized {
                subscriber.putNext(.denied)
                subscriber.putCompletion()
                return
            }
            innerDisposable = saveToCameraRoll(context: context, userLocation: userLocation, mediaReference: mediaReference, video: video).start(completed: {
                subscriber.putNext(.saved)
                subscriber.putCompletion()
            })
        })
        return ActionDisposable {
            innerDisposable?.dispose()
        }
    }
}
