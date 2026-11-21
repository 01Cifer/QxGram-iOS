import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import SaveToCameraRoll
import LegacyMediaPickerUI
import PresentationDataUtils
import OverlayStatusController

public func qxGramCanSaveMedia(_ message: Message, peerIsCopyProtected: Bool, accountId: AccountRecordId) -> Bool {
    if message.paidContent != nil {
        return false
    }
    if QxGramAlwaysSavePolicy.isEnabled(accountId: accountId) {
        return true
    }
    return !message.isCopyProtected() && !peerIsCopyProtected
}

private func qxGramSaveToFilesExtension(_ mediaReference: AnyMediaReference) -> String {
    if let file = mediaReference.media as? TelegramMediaFile {
        if let fileName = file.fileName {
            let value = (fileName as NSString).pathExtension
            if !value.isEmpty, value.count <= 16, value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) {
                return value
            }
        }
        if file.isVideo {
            return "mp4"
        }
        if file.isMusic {
            return "mp3"
        }
    }
    return "jpg"
}

/// Downloads the medium and hands it to the system "Save to Files" picker with progress and errors.
public func qxGramSaveToFiles(context: AccountContext, mediaReference: AnyMediaReference, present: @escaping (ViewController, Any?) -> Void) -> Disposable {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    var cancelImpl: (() -> Void)?
    let progressSignal = Signal<Never, NoError> { _ in
        let controller = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: {
            cancelImpl?()
        }))
        present(controller, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
        return ActionDisposable { [weak controller] in
            Queue.mainQueue().async {
                controller?.dismiss()
            }
        }
    }
    |> runOn(Queue.mainQueue())
    |> delay(0.15, queue: Queue.mainQueue())
    let progressDisposable = progressSignal.startStrict()

    let disposable = MetaDisposable()
    cancelImpl = { [weak disposable] in
        disposable?.set(nil)
    }

    var finished = false
    let showError = {
        guard !finished else {
            return
        }
        finished = true
        progressDisposable.dispose()
        let alert = textAlertController(context: context, title: "QxGram", text: "Не удалось скачать медиа для сохранения. Проверьте соединение и попробуйте снова.", actions: [
            TextAlertAction(type: .defaultAction, title: "OK", action: {})
        ])
        present(alert, nil)
    }

    let fetchSignal: Signal<String?, NoError> = fetchMediaData(context: context, userLocation: .other, mediaReference: mediaReference)
    |> map { state, _ -> String? in
        if case let .data(data) = state, data.isComplete {
            return data.path
        }
        return nil
    }
    |> SwiftSignalKit.filter { $0 != nil }
    |> take(1)
    |> timeout(30.0, queue: Queue.mainQueue(), alternate: .single(nil))

    disposable.set((fetchSignal
    |> deliverOnMainQueue).startStrict(next: { sourcePath in
        guard let sourcePath else {
            showError()
            return
        }
        let path = NSTemporaryDirectory() + "qxgram-save-\(Int64.random(in: Int64.min ... Int64.max)).\(qxGramSaveToFilesExtension(mediaReference))"
        try? FileManager.default.removeItem(atPath: path)
        guard (try? FileManager.default.linkItem(atPath: sourcePath, toPath: path)) != nil else {
            showError()
            return
        }
        finished = true
        progressDisposable.dispose()
        let controller = legacyICloudFilePicker(theme: presentationData.theme, mode: .export, url: URL(fileURLWithPath: path), documentTypes: [], forceDarkTheme: false, dismissed: {}, completion: { _ in })
        present(controller, nil)
    }, completed: {
        showError()
    }))

    return disposable
}
