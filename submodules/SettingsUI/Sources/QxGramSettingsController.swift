import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext

private struct QxGramCacheStatus: Equatable {
    var size: Int64?
    var isClearing: Bool
}

private final class QxGramCacheState {
    private let context: AccountContext
    private let statsDisposable = MetaDisposable()
    private var status = QxGramCacheStatus(size: nil, isClearing: false) {
        didSet {
            self.promise.set(self.status)
        }
    }
    let promise = ValuePromise(QxGramCacheStatus(size: nil, isClearing: false), ignoreRepeated: true)

    init(context: AccountContext) {
        self.context = context
        self.reload()
    }

    deinit {
        self.statsDisposable.dispose()
    }

    private func reload() {
        self.status = QxGramCacheStatus(size: nil, isClearing: false)
        self.statsDisposable.set((self.context.engine.resources.collectStorageUsageStats()
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] stats in
            guard let self else {
                return
            }
            let size = stats.totalStats.categories.values.reduce(Int64(0)) { $0 + $1.size }
            self.status = QxGramCacheStatus(size: size, isClearing: false)
        }))
    }

    func clear() {
        guard !self.status.isClearing, self.status.size != nil else {
            return
        }
        self.statsDisposable.set(nil)
        self.status = QxGramCacheStatus(size: self.status.size, isClearing: true)
        let _ = (self.context.engine.resources.clearStorage(peerId: nil, categories: [.photos, .videos, .files, .music, .stickers, .avatars, .misc, .stories], includeMessages: [], excludeMessages: [])
        |> deliverOnMainQueue).startStandalone(completed: { [weak self] in
            self?.reload()
        })
    }
}

private final class QxGramSettingsArguments {
    let settings: QxGramSettings
    let clearCache: () -> Void

    init(settings: QxGramSettings, clearCache: @escaping () -> Void) {
        self.settings = settings
        self.clearCache = clearCache
    }
}

private enum QxGramSettingsEntry: ItemListNodeEntry {
    case ghost(Bool)
    case deleted(Bool)
    case ttl(Bool)
    case showTtl(Bool)
    case screenshots(Bool)
    case callRecording(Bool)
    case alwaysForward(Bool)
    case pendingNotice
    case cache(String, Bool)
    case cacheNotice

    var section: ItemListSectionId {
        switch self {
        case .cache, .cacheNotice:
            return 1
        default:
            return 0
        }
    }

    var stableId: Int32 {
        switch self {
        case .ghost:
            return 0
        case .deleted:
            return 1
        case .ttl:
            return 2
        case .showTtl:
            return 3
        case .screenshots:
            return 4
        case .callRecording:
            return 5
        case .alwaysForward:
            return 6
        case .pendingNotice:
            return 7
        case .cache:
            return 8
        case .cacheNotice:
            return 9
        }
    }

    static func <(lhs: QxGramSettingsEntry, rhs: QxGramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! QxGramSettingsArguments
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
        case let .showTtl(current):
            title = "Показывать TTL"
            setting = .showTtl
            value = current
        case let .screenshots(current):
            title = "Разрешить скриншот"
            setting = .allowScreenshots
            value = current
        case let .callRecording(current):
            title = "Запись звонков"
            setting = .callRecording
            value = current
        case let .alwaysForward(current):
            title = "Всегда пересылать"
            setting = .alwaysForward
            value = current
        case .pendingNotice:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Все функции QxGram активны: архив удалённых, TTL-медиа, скриншоты, Ghost. Переключатели применяются сразу."), sectionId: self.section)
        case let .cache(label, isEnabled):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Очистить кэш", enabled: isEnabled, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                arguments.clearCache()
            })
        case .cacheNotice:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Очищается учитываемый Telegram кэш текущего аккаунта. Некоторые файлы могут быть недоступны для повторной загрузки. Сообщения не удаляются."), sectionId: self.section)
        }
        return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
            arguments.settings.set(setting, value: value)
        })
    }
}

private func qxGramSettingsEntries(_ settings: QxGramSettings) -> [QxGramSettingsEntry] {
    return [
        .ghost(settings.value(.ghost)),
        .deleted(settings.value(.showDeletedMessages)),
        .ttl(settings.value(.saveTtlMedia)),
        .showTtl(settings.value(.showTtl)),
        .screenshots(settings.value(.allowScreenshots)),
        .callRecording(settings.value(.callRecording)),
        .alwaysForward(settings.value(.alwaysForward)),
        .pendingNotice
    ]
}

public func qxGramSettingsController(context: AccountContext) -> ViewController {
    let settings = QxGramSettings(accountId: context.account.id)
    let cacheState = QxGramCacheState(context: context)
    var presentClearCache: (() -> Void)?
    let arguments = QxGramSettingsArguments(settings: settings, clearCache: {
        presentClearCache?()
    })
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
    let signal = combineLatest(context.sharedContext.presentationData, settingsSignal, cacheState.promise.get())
    |> deliverOnMainQueue
    |> map { presentationData, entries, cacheStatus -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let itemPresentationData = ItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(presentationData: itemPresentationData, title: .text("Настройки QxGram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let cacheLabel: String
        if cacheStatus.isClearing {
            cacheLabel = "Очистка…"
        } else if let size = cacheStatus.size {
            cacheLabel = dataSizeString(size, formatting: DataSizeStringFormatting(presentationData: presentationData))
        } else {
            cacheLabel = "Подсчёт…"
        }
        let allEntries = entries + [.cache(cacheLabel, !cacheStatus.isClearing && cacheStatus.size != nil), .cacheNotice]
        let listState = ItemListNodeState(presentationData: itemPresentationData, entries: allEntries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    presentClearCache = { [weak controller] in
        guard let controller else {
            return
        }
        controller.present(textAlertController(context: context, title: "Очистить кэш?", text: "Удалить загруженные данные текущего аккаунта? Некоторые файлы могут быть недоступны для повторной загрузки.", actions: [
            TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
            TextAlertAction(type: .defaultAction, title: "Продолжить", action: { [weak controller] in
                Queue.mainQueue().after(0.4, {
                    guard let controller else {
                        return
                    }
                    controller.present(textAlertController(context: context, title: "Удалить кэш?", text: "Подтвердите очистку учитываемого Telegram кэша текущего аккаунта. Сообщения не удаляются.", actions: [
                        TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
                        TextAlertAction(type: .destructiveAction, title: "Удалить всё", action: {
                            cacheState.clear()
                        })
                    ]), in: .window(.root))
                })
            })
        ]), in: .window(.root))
    }
    return controller
}
