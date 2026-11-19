import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext

private enum QxGramSettingsEntry: ItemListNodeEntry {
    case ghost(Bool)
    case deleted(Bool)
    case ttl(Bool)
    case screenshots(Bool)
    case pendingNotice

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .ghost:
            return 0
        case .deleted:
            return 1
        case .ttl:
            return 2
        case .screenshots:
            return 3
        case .pendingNotice:
            return 4
        }
    }

    static func <(lhs: QxGramSettingsEntry, rhs: QxGramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let settings = arguments as! QxGramSettings
        let title: String
        let setting: QxGramSetting
        let value: Bool
        switch self {
        case let .ghost(current):
            title = "Ghost"
            setting = .ghost
            value = current
        case let .deleted(current):
            title = "Показывать удалённые"
            setting = .showDeletedMessages
            value = current
        case let .ttl(current):
            title = "Сохранять TTL-медиа"
            setting = .saveTtlMedia
            value = current
        case let .screenshots(current):
            title = "Разрешить скриншот"
            setting = .allowScreenshots
            value = current
        case .pendingNotice:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Переключатели сохраняются, но функции Ghost, удалённых сообщений, TTL и скриншотов пока не реализованы."), sectionId: self.section)
        }
        return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
            settings.set(setting, value: value)
        })
    }
}

private func qxGramSettingsEntries(_ settings: QxGramSettings) -> [QxGramSettingsEntry] {
    return [
        .ghost(settings.value(.ghost)),
        .deleted(settings.value(.showDeletedMessages)),
        .ttl(settings.value(.saveTtlMedia)),
        .screenshots(settings.value(.allowScreenshots)),
        .pendingNotice
    ]
}

public func qxGramSettingsController(context: AccountContext) -> ViewController {
    let settings = QxGramSettings(accountId: context.account.id)
    let settingsSignal = Signal<[QxGramSettingsEntry], NoError> { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: .qxGramSettingsDidChange, object: nil, queue: .main, using: { notification in
            guard let accountId = notification.userInfo?["accountId"] as? Int64, accountId == settings.accountId.int64 else {
                return
            }
            subscriber.putNext(qxGramSettingsEntries(settings))
        })
        subscriber.putNext(qxGramSettingsEntries(settings))
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    let signal = combineLatest(context.sharedContext.presentationData, settingsSignal)
    |> deliverOnMainQueue
    |> map { presentationData, entries -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let itemPresentationData = ItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(presentationData: itemPresentationData, title: .text("Настройки QxGram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: itemPresentationData, entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, settings))
    }
    return ItemListController(context: context, state: signal)
}
