import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import ChatListUI
import TelegramPresentationData
import PresentationDataUtils
import OverlayStatusController
import SaveToCameraRoll

extension ChatControllerImpl {
    func copyForwardMessages(messages: [EngineRawMessage]) {
        let supported = messages.filter { qxGramCanCopyForwardAsNew($0) }
        guard !supported.isEmpty else {
            return
        }

        let context = self.context
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        var cancelImpl: (() -> Void)?
        let progressSignal = Signal<Never, NoError> { _ in
            let controller = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: {
                cancelImpl?()
            }))
            self.present(controller, in: .window(.root))
            return ActionDisposable { [weak controller] in
                Queue.mainQueue().async {
                    controller?.dismiss()
                }
            }
        }
        |> runOn(Queue.mainQueue())
        |> delay(0.15, queue: Queue.mainQueue())

        let progressDisposable = progressSignal.startStrict()

        let fetchSignals: [Signal<Bool, NoError>] = supported.compactMap { message in
            guard let media = message.effectiveMedia.first else {
                return nil
            }
            let reference: AnyMediaReference
            if message.id.peerId.namespace == Namespaces.Peer.SecretChat || message.id.namespace == Namespaces.Message.Local || message.id.namespace == Namespaces.Message.EphemeralLocal {
                reference = .standalone(media: media)
            } else {
                reference = .message(message: MessageReference(message), media: media)
            }
            return fetchMediaData(context: context, userLocation: .other, mediaReference: reference)
            |> map { state, _ -> Bool in
                if case let .data(data) = state {
                    return data.isComplete
                }
                return false
            }
            |> SwiftSignalKit.filter { $0 }
            |> take(1)
        }

        let fetchDisposable = MetaDisposable()
        let combineSignal: Signal<[Bool], NoError>
        if fetchSignals.isEmpty {
            combineSignal = .single([])
        } else {
            combineSignal = combineLatest(fetchSignals)
        }
        cancelImpl = { [weak fetchDisposable] in
            fetchDisposable?.set(nil)
        }
        fetchDisposable.set((combineSignal
        |> timeout(30.0, queue: Queue.mainQueue(), alternate: .single([false]))
        |> deliverOnMainQueue).startStrict(next: { [weak self] results in
            guard let self else {
                return
            }
            progressDisposable.dispose()
            if results.contains(false) {
                let alert = textAlertController(context: context, title: "QxGram", text: "Не удалось скачать медиа для пересылки. Проверьте соединение и попробуйте снова.", actions: [
                    TextAlertAction(type: .defaultAction, title: "OK", action: {})
                ])
                self.present(alert, in: .window(.root))
            } else {
                self.presentCopyForwardPicker(messages: supported)
            }
        }, completed: {
            progressDisposable.dispose()
        }))
    }

    private func presentCopyForwardPicker(messages: [EngineRawMessage]) {
        let filter: ChatListNodePeersFilter = [.onlyWriteable, .excludeDisabled, .doNotSearchMessages]
        let controller = self.context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: self.context, updatedPresentationData: self.updatedPresentationData, filter: filter, hasFilters: true, attemptSelection: { _, _, _ in
        }, multipleSelection: true, forwardedMessageIds: messages.map { $0.id }, selectForumThreads: true))

        let commit: ([EnginePeer]) -> Void = { [weak self, weak controller] peers in
            guard let self, let controller else {
                return
            }
            controller.dismiss()
            var enqueue = qxGramCopyForwardEnqueueMessages(messages)
            for i in 0 ..< enqueue.count {
                enqueue[i] = enqueue[i].withUpdatedCorrelationId(Int64.random(in: Int64.min ... Int64.max))
            }
            for peer in peers {
                let _ = (enqueueMessages(account: self.context.account, peerId: peer.id, messages: enqueue)
                |> deliverOnMainQueue).startStandalone(next: { _ in })
            }
            self.updateChatPresentationInterfaceState(animated: false, interactive: true, { $0.updatedInterfaceState({ $0.withoutSelectionState() }).updatedSearch(nil) })
        }

        controller.multiplePeersSelected = { peers, _, _, _, _, _ in
            commit(peers)
        }
        controller.peerSelected = { peer, _ in
            commit([peer])
        }
        self.chatDisplayNode.dismissInput()
        self.effectiveNavigationController?.pushViewController(controller)
    }
}
