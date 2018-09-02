import Foundation
import Display
import AsyncDisplayKit
import Postbox
import TelegramCore
import SwiftSignalKit

private struct PeerSpecificPackData {
    let peer: Peer
    let info: StickerPackCollectionInfo
    let items: [ItemCollectionItem]
}

private enum CanInstallPeerSpecificPack {
    case none
    case available(dismissed: Bool)
}

private struct ChatMediaInputPanelTransition {
    let deletions: [ListViewDeleteItem]
    let insertions: [ListViewInsertItem]
    let updates: [ListViewUpdateItem]
}

private struct ChatMediaInputGridTransition {
    let deletions: [Int]
    let insertions: [GridNodeInsertItem]
    let updates: [GridNodeUpdateItem]
    let updateFirstIndexInSectionOffset: Int?
    let stationaryItems: GridNodeStationaryItems
    let scrollToItem: GridNodeScrollToItem?
    let updateOpaqueState: ChatMediaInputStickerPaneOpaqueState?
    let animated: Bool
}

private func preparedChatMediaInputPanelEntryTransition(account: Account, from fromEntries: [ChatMediaInputPanelEntry], to toEntries: [ChatMediaInputPanelEntry], inputNodeInteraction: ChatMediaInputNodeInteraction) -> ChatMediaInputPanelTransition {
    let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: fromEntries, rightList: toEntries)
    
    let deletions = deleteIndices.map { ListViewDeleteItem(index: $0, directionHint: nil) }
    let insertions = indicesAndItems.map { ListViewInsertItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(account: account, inputNodeInteraction: inputNodeInteraction), directionHint: nil) }
    let updates = updateIndices.map { ListViewUpdateItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(account: account, inputNodeInteraction: inputNodeInteraction), directionHint: nil) }
    
    return ChatMediaInputPanelTransition(deletions: deletions, insertions: insertions, updates: updates)
}

private func preparedChatMediaInputGridEntryTransition(account: Account, view: ItemCollectionsView, from fromEntries: [ChatMediaInputGridEntry], to toEntries: [ChatMediaInputGridEntry], update: StickerPacksCollectionUpdate, interfaceInteraction: ChatControllerInteraction, inputNodeInteraction: ChatMediaInputNodeInteraction) -> ChatMediaInputGridTransition {
    var stationaryItems: GridNodeStationaryItems = .none
    var scrollToItem: GridNodeScrollToItem?
    var animated = false
    switch update {
        case .initial:
            for i in (0 ..< toEntries.count).reversed() {
                switch toEntries[i] {
                    case .search, .peerSpecificSetup:
                        break
                    case .sticker:
                        scrollToItem = GridNodeScrollToItem(index: i, position: .top, transition: .animated(duration: 0.0, curve: .easeInOut), directionHint: .down, adjustForSection: true, adjustForTopInset: true)
                }
            }
        case .generic:
            animated = true
        case .scroll:
            var fromStableIds = Set<ChatMediaInputGridEntryStableId>()
            for entry in fromEntries {
                fromStableIds.insert(entry.stableId)
            }
            var index = 0
            var indices = Set<Int>()
            for entry in toEntries {
                if fromStableIds.contains(entry.stableId) {
                    indices.insert(index)
                }
                index += 1
            }
            stationaryItems = .indices(indices)
        case let .navigate(index, collectionId):
            if let index = index.flatMap({ ChatMediaInputGridEntryIndex.collectionIndex($0) }) {
                for i in 0 ..< toEntries.count {
                    if toEntries[i].index >= index {
                        var directionHint: GridNodePreviousItemsTransitionDirectionHint = .up
                        if !fromEntries.isEmpty && fromEntries[0].index < toEntries[i].index {
                            directionHint = .down
                        }
                        scrollToItem = GridNodeScrollToItem(index: i, position: .top, transition: .animated(duration: 0.45, curve: .spring), directionHint: directionHint, adjustForSection: true, adjustForTopInset: true)
                        break
                    }
                }
            } else if !toEntries.isEmpty {
                if let collectionId = collectionId {
                    for i in 0 ..< toEntries.count {
                        if case let .collectionIndex(collectionIndex) = toEntries[i].index, collectionIndex.collectionId == collectionId {
                            var directionHint: GridNodePreviousItemsTransitionDirectionHint = .up
                            if !fromEntries.isEmpty && fromEntries[0].index < toEntries[i].index {
                                directionHint = .down
                            }
                            scrollToItem = GridNodeScrollToItem(index: i, position: .top, transition: .animated(duration: 0.45, curve: .spring), directionHint: directionHint, adjustForSection: true, adjustForTopInset: true)
                            break
                        }
                    }
                }
                if scrollToItem == nil {
                    scrollToItem = GridNodeScrollToItem(index: 0, position: .top, transition: .animated(duration: 0.45, curve: .spring), directionHint: .up, adjustForSection: true, adjustForTopInset: true)
                }
            }
    }
    
    let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: fromEntries, rightList: toEntries)
    
    let deletions = deleteIndices
    let insertions = indicesAndItems.map { GridNodeInsertItem(index: $0.0, item: $0.1.item(account: account, interfaceInteraction: interfaceInteraction, inputNodeInteraction: inputNodeInteraction), previousIndex: $0.2) }
    let updates = updateIndices.map { GridNodeUpdateItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(account: account, interfaceInteraction: interfaceInteraction, inputNodeInteraction: inputNodeInteraction)) }
    
    var firstIndexInSectionOffset = 0
    if !toEntries.isEmpty {
        switch toEntries[0].index {
            case .search, .peerSpecificSetup:
                break
            case let .collectionIndex(index):
                firstIndexInSectionOffset = Int(index.itemIndex.index)
        }
    }
    
    if case .initial = update {
        switch toEntries[0].index {
            case .search:
                if toEntries.count > 1 {
                    //scrollToItem = GridNodeScrollToItem(index: 1, position: .top, transition: .immediate, directionHint: .up, adjustForSection: true)
                }
                break
            default:
                break
        }
    }
    
    let opaqueState = ChatMediaInputStickerPaneOpaqueState(hasLower: view.lower != nil)
    
    return ChatMediaInputGridTransition(deletions: deletions, insertions: insertions, updates: updates, updateFirstIndexInSectionOffset: firstIndexInSectionOffset, stationaryItems: stationaryItems, scrollToItem: scrollToItem, updateOpaqueState: opaqueState, animated: animated)
}

private func chatMediaInputPanelEntries(view: ItemCollectionsView, savedStickers: OrderedItemListView?, recentStickers: OrderedItemListView?, peerSpecificPack: PeerSpecificPackData?, theme: PresentationTheme) -> [ChatMediaInputPanelEntry] {
    var entries: [ChatMediaInputPanelEntry] = []
    entries.append(.recentGifs(theme))
    if let savedStickers = savedStickers, !savedStickers.items.isEmpty {
        entries.append(.savedStickers(theme))
    }
    var savedStickerIds = Set<Int64>()
    if let savedStickers = savedStickers, !savedStickers.items.isEmpty {
        for i in 0 ..< savedStickers.items.count {
            if let item = savedStickers.items[i].contents as? SavedStickerItem {
                savedStickerIds.insert(item.file.fileId.id)
            }
        }
    }
    if let recentStickers = recentStickers, !recentStickers.items.isEmpty {
        var found = false
        for item in recentStickers.items {
            if let item = item.contents as? RecentMediaItem, let _ = item.media as? TelegramMediaFile, let mediaId = item.media.id {
                if !savedStickerIds.contains(mediaId.id) {
                    found = true
                    break
                }
            }
        }
        if found {
            entries.append(.recentPacks(theme))
        }
    }
    if let peerSpecificPack = peerSpecificPack {
        entries.append(.peerSpecific(theme: theme, peer: peerSpecificPack.peer))
    }
    var index = 0
    for (_, info, item) in view.collectionInfos {
        if let info = info as? StickerPackCollectionInfo {
            entries.append(.stickerPack(index: index, info: info, topItem: item as? StickerPackItem, theme: theme))
            index += 1
        }
    }
    entries.append(.trending(false, theme))
    entries.append(.settings(theme))
    return entries
}

private func chatMediaInputGridEntries(view: ItemCollectionsView, savedStickers: OrderedItemListView?, recentStickers: OrderedItemListView?, peerSpecificPack: PeerSpecificPackData?, canInstallPeerSpecificPack: CanInstallPeerSpecificPack, strings: PresentationStrings, theme: PresentationTheme) -> [ChatMediaInputGridEntry] {
    var entries: [ChatMediaInputGridEntry] = []
    
    if view.lower == nil {
        entries.append(.search(theme: theme, strings: strings))
    }
    
    var stickerPackInfos: [ItemCollectionId: StickerPackCollectionInfo] = [:]
    for (id, info, _) in view.collectionInfos {
        if let info = info as? StickerPackCollectionInfo {
            stickerPackInfos[id] = info
        }
    }
    
    if view.lower == nil {
        var savedStickerIds = Set<Int64>()
        if let savedStickers = savedStickers, !savedStickers.items.isEmpty {
            let packInfo = StickerPackCollectionInfo(id: ItemCollectionId(namespace: ChatMediaInputPanelAuxiliaryNamespace.savedStickers.rawValue, id: 0), flags: [], accessHash: 0, title: strings.Stickers_FavoriteStickers.uppercased(), shortName: "", hash: 0, count: 0)
            for i in 0 ..< savedStickers.items.count {
                if let item = savedStickers.items[i].contents as? SavedStickerItem {
                    savedStickerIds.insert(item.file.fileId.id)
                    let index = ItemCollectionItemIndex(index: Int32(i), id: item.file.fileId.id)
                    let stickerItem = StickerPackItem(index: index, file: item.file, indexKeys: [])
                    entries.append(.sticker(index: ItemCollectionViewEntryIndex(collectionIndex: -3, collectionId: packInfo.id, itemIndex: index), stickerItem: stickerItem, stickerPackInfo: packInfo, theme: theme))
                }
            }
        }
        
        if let recentStickers = recentStickers, !recentStickers.items.isEmpty {
            let packInfo = StickerPackCollectionInfo(id: ItemCollectionId(namespace: ChatMediaInputPanelAuxiliaryNamespace.recentStickers.rawValue, id: 0), flags: [], accessHash: 0, title: strings.Stickers_FrequentlyUsed.uppercased(), shortName: "", hash: 0, count: 0)
            var addedCount = 0
            for i in 0 ..< recentStickers.items.count {
                if addedCount >= 20 {
                    break
                }
                if let item = recentStickers.items[i].contents as? RecentMediaItem, let file = item.media as? TelegramMediaFile, let mediaId = item.media.id {
                    if !savedStickerIds.contains(mediaId.id) {
                        let index = ItemCollectionItemIndex(index: Int32(i), id: mediaId.id)
                        let stickerItem = StickerPackItem(index: index, file: file, indexKeys: [])
                        entries.append(.sticker(index: ItemCollectionViewEntryIndex(collectionIndex: -2, collectionId: packInfo.id, itemIndex: index), stickerItem: stickerItem, stickerPackInfo: packInfo, theme: theme))
                        addedCount += 1
                    }
                }
            }
        }
        
        if peerSpecificPack == nil, case .available(false) = canInstallPeerSpecificPack {
            entries.append(.peerSpecificSetup(theme: theme, strings: strings, dismissed: false))
        }
        
        if let peerSpecificPack = peerSpecificPack {
            for i in 0 ..< peerSpecificPack.items.count {
                let packInfo = StickerPackCollectionInfo(id: ItemCollectionId(namespace: ChatMediaInputPanelAuxiliaryNamespace.peerSpecific.rawValue, id: 0), flags: [], accessHash: 0, title: strings.Stickers_GroupStickers, shortName: "", hash: 0, count: 0)
                
                if let item = peerSpecificPack.items[i] as? StickerPackItem {
                    let index = ItemCollectionItemIndex(index: Int32(i), id: item.file.fileId.id)
                    let stickerItem = StickerPackItem(index: index, file: item.file, indexKeys: [])
                    entries.append(.sticker(index: ItemCollectionViewEntryIndex(collectionIndex: -1, collectionId: packInfo.id, itemIndex: index), stickerItem: stickerItem, stickerPackInfo: packInfo, theme: theme))
                }
            }
        }
    }
    
    for entry in view.entries {
        if let item = entry.item as? StickerPackItem {
            entries.append(.sticker(index: entry.index, stickerItem: item, stickerPackInfo: stickerPackInfos[entry.index.collectionId], theme: theme))
        }
    }
    
    if view.higher == nil {
        if peerSpecificPack == nil, case .available(true) = canInstallPeerSpecificPack {
            entries.append(.peerSpecificSetup(theme: theme, strings: strings, dismissed: true))
        }
    }
    return entries
}

private enum StickerPacksCollectionPosition: Equatable {
    case initial
    case scroll(aroundIndex: ItemCollectionViewEntryIndex?)
    case navigate(index: ItemCollectionViewEntryIndex?, collectionId: ItemCollectionId?)
    
    static func ==(lhs: StickerPacksCollectionPosition, rhs: StickerPacksCollectionPosition) -> Bool {
        switch lhs {
            case .initial:
                if case .initial = rhs {
                    return true
                } else {
                    return false
                }
            case let .scroll(lhsAroundIndex):
                if case let .scroll(rhsAroundIndex) = rhs, lhsAroundIndex == rhsAroundIndex {
                    return true
                } else {
                    return false
                }
            case .navigate:
                return false
        }
    }
}

private enum StickerPacksCollectionUpdate {
    case initial
    case generic
    case scroll
    case navigate(ItemCollectionViewEntryIndex?, ItemCollectionId?)
}

final class ChatMediaInputNodeInteraction {
    let navigateToCollectionId: (ItemCollectionId) -> Void
    let openSettings: () -> Void
    let toggleSearch: (Bool) -> Void
    let openPeerSpecificSettings: () -> Void
    let dismissPeerSpecificSettings: () -> Void
    
    var highlightedStickerItemCollectionId: ItemCollectionId?
    var highlightedItemCollectionId: ItemCollectionId?
    var previewedStickerPackItem: StickerPreviewPeekItem?
    var appearanceTransition: CGFloat = 1.0
    
    init(navigateToCollectionId: @escaping (ItemCollectionId) -> Void, openSettings: @escaping () -> Void, toggleSearch: @escaping (Bool) -> Void, openPeerSpecificSettings: @escaping () -> Void, dismissPeerSpecificSettings: @escaping () -> Void) {
        self.navigateToCollectionId = navigateToCollectionId
        self.openSettings = openSettings
        self.toggleSearch = toggleSearch
        self.openPeerSpecificSettings = openPeerSpecificSettings
        self.dismissPeerSpecificSettings = dismissPeerSpecificSettings
    }
}

private func clipScrollPosition(_ position: StickerPacksCollectionPosition) -> StickerPacksCollectionPosition {
    switch position {
        case let .scroll(index):
            if let index = index, index.collectionId.namespace == ChatMediaInputPanelAuxiliaryNamespace.savedStickers.rawValue || index.collectionId.namespace == ChatMediaInputPanelAuxiliaryNamespace.recentStickers.rawValue {
                return .scroll(aroundIndex: nil)
            }
        default:
            break
    }
    return position
}

private enum ChatMediaInputPaneType {
    case gifs
    case stickers
    case trending
}

private struct ChatMediaInputPaneArrangement {
    let panes: [ChatMediaInputPaneType]
    let currentIndex: Int
    let indexTransition: CGFloat
    
    func withIndexTransition(_ indexTransition: CGFloat) -> ChatMediaInputPaneArrangement {
        return ChatMediaInputPaneArrangement(panes: self.panes, currentIndex: currentIndex, indexTransition: indexTransition)
    }
    
    func withCurrentIndex(_ currentIndex: Int) -> ChatMediaInputPaneArrangement {
        return ChatMediaInputPaneArrangement(panes: self.panes, currentIndex: currentIndex, indexTransition: self.indexTransition)
    }
}

private final class CollectionListContainerNode: ASDisplayNode {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for subview in self.view.subviews {
            if let result = subview.hitTest(point.offsetBy(dx: -subview.frame.minX, dy: -subview.frame.minY), with: event) {
                return result
            }
        }
        return nil
    }
}

final class ChatMediaInputNode: ChatInputNode {
    private let account: Account
    private let peerId: PeerId?
    private let controllerInteraction: ChatControllerInteraction
    private let gifPaneIsActiveUpdated: (Bool) -> Void
    
    private var inputNodeInteraction: ChatMediaInputNodeInteraction!
    
    private let collectionListPanel: ASDisplayNode
    private let collectionListSeparator: ASDisplayNode
    private let collectionListContainer: CollectionListContainerNode
    
    private let disposable = MetaDisposable()
    
    private let listView: ListView
    private var stickerSearchContainerNode: StickerPaneSearchContainerNode?
    
    private let stickerPane: ChatMediaInputStickerPane
    private var animatingStickerPaneOut = false
    private let gifPane: ChatMediaInputGifPane
    private var animatingGifPaneOut = false
    private let trendingPane: ChatMediaInputTrendingPane
    private var animatingTrendingPaneOut = false
    
    private var panRecognizer: UIPanGestureRecognizer?
    
    private let itemCollectionsViewPosition = Promise<StickerPacksCollectionPosition>()
    private var currentStickerPacksCollectionPosition: StickerPacksCollectionPosition?
    private var currentView: ItemCollectionsView?
    private let dismissedPeerSpecificStickerPack = Promise<Bool>()
    
    private var validLayout: (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, ChatPresentationInterfaceState)?
    private var paneArrangement: ChatMediaInputPaneArrangement
    private var initializedArrangement = false
    
    private var theme: PresentationTheme
    private var strings: PresentationStrings
    private let themeAndStringsPromise: Promise<(PresentationTheme, PresentationStrings)>
    
    init(account: Account, peerId: PeerId?, controllerInteraction: ChatControllerInteraction, theme: PresentationTheme, strings: PresentationStrings, gifPaneIsActiveUpdated: @escaping (Bool) -> Void) {
        self.account = account
        self.peerId = peerId
        self.controllerInteraction = controllerInteraction
        self.theme = theme
        self.strings = strings
        self.gifPaneIsActiveUpdated = gifPaneIsActiveUpdated
        
        self.themeAndStringsPromise = Promise((theme, strings))
        
        self.collectionListPanel = ASDisplayNode()
        self.collectionListPanel.clipsToBounds = true
        self.collectionListPanel.backgroundColor = theme.chat.inputPanel.panelBackgroundColor
        
        self.collectionListSeparator = ASDisplayNode()
        self.collectionListSeparator.isLayerBacked = true
        self.collectionListSeparator.backgroundColor = theme.chat.inputMediaPanel.panelSerapatorColor
        
        self.collectionListContainer = CollectionListContainerNode()
        self.collectionListContainer.clipsToBounds = true
        
        self.listView = ListView()
        self.listView.transform = CATransform3DMakeRotation(-CGFloat(Double.pi / 2.0), 0.0, 0.0, 1.0)
        
        var paneDidScrollImpl: ((ChatMediaInputPane, ChatMediaInputPaneScrollState, ContainedViewLayoutTransition) -> Void)?
        var fixPaneScrollImpl: ((ChatMediaInputPane, ChatMediaInputPaneScrollState) -> Void)?
        
        self.stickerPane = ChatMediaInputStickerPane(theme: theme, strings: strings, paneDidScroll: { pane, state, transition in
            paneDidScrollImpl?(pane, state, transition)
        }, fixPaneScroll: { pane, state in
            fixPaneScrollImpl?(pane, state)
        })
        self.gifPane = ChatMediaInputGifPane(account: account, theme: theme, strings: strings, controllerInteraction: controllerInteraction, paneDidScroll: { pane, state, transition in
            paneDidScrollImpl?(pane, state, transition)
        }, fixPaneScroll: { pane, state in
            fixPaneScrollImpl?(pane, state)
        })
        
        var getItemIsPreviewedImpl: ((StickerPackItem) -> Bool)?
        self.trendingPane = ChatMediaInputTrendingPane(account: account, controllerInteraction: controllerInteraction, getItemIsPreviewed: { item in
            return getItemIsPreviewedImpl?(item) ?? false
        })
        
        self.paneArrangement = ChatMediaInputPaneArrangement(panes: [.gifs, .stickers, .trending], currentIndex: 1, indexTransition: 0.0)
        
        super.init()
        
        self.inputNodeInteraction = ChatMediaInputNodeInteraction(navigateToCollectionId: { [weak self] collectionId in
            if let strongSelf = self, let currentView = strongSelf.currentView, (collectionId != strongSelf.inputNodeInteraction.highlightedItemCollectionId || true) {
                var index: Int32 = 0
                if collectionId.namespace == ChatMediaInputPanelAuxiliaryNamespace.recentGifs.rawValue {
                    strongSelf.setCurrentPane(.gifs, transition: .animated(duration: 0.25, curve: .spring))
                } else if collectionId.namespace == ChatMediaInputPanelAuxiliaryNamespace.trending.rawValue {
                    strongSelf.setCurrentPane(.trending, transition: .animated(duration: 0.25, curve: .spring))
                } else if collectionId.namespace == ChatMediaInputPanelAuxiliaryNamespace.savedStickers.rawValue {
                    strongSelf.setCurrentPane(.stickers, transition: .animated(duration: 0.25, curve: .spring))
                    strongSelf.currentStickerPacksCollectionPosition = .navigate(index: nil, collectionId: collectionId)
                    strongSelf.itemCollectionsViewPosition.set(.single(.navigate(index: nil, collectionId: collectionId)))
                } else if collectionId.namespace == ChatMediaInputPanelAuxiliaryNamespace.recentStickers.rawValue {
                    strongSelf.setCurrentPane(.stickers, transition: .animated(duration: 0.25, curve: .spring))
                    strongSelf.currentStickerPacksCollectionPosition = .navigate(index: nil, collectionId: collectionId)
                    strongSelf.itemCollectionsViewPosition.set(.single(.navigate(index: nil, collectionId: collectionId)))
                } else if collectionId.namespace == ChatMediaInputPanelAuxiliaryNamespace.peerSpecific.rawValue {
                    strongSelf.setCurrentPane(.stickers, transition: .animated(duration: 0.25, curve: .spring))
                    strongSelf.currentStickerPacksCollectionPosition = .navigate(index: nil, collectionId: collectionId)
                    strongSelf.itemCollectionsViewPosition.set(.single(.navigate(index: nil, collectionId: collectionId)))
                } else {
                    strongSelf.setCurrentPane(.stickers, transition: .animated(duration: 0.25, curve: .spring))
                    for (id, _, _) in currentView.collectionInfos {
                        if id.namespace == collectionId.namespace {
                            if id == collectionId {
                                let itemIndex = ItemCollectionViewEntryIndex.lowerBound(collectionIndex: index, collectionId: id)
                                strongSelf.currentStickerPacksCollectionPosition = .navigate(index: itemIndex, collectionId: nil)
                                strongSelf.itemCollectionsViewPosition.set(.single(.navigate(index: itemIndex, collectionId: nil)))
                                break
                            }
                            index += 1
                        }
                    }
                }
            }
        }, openSettings: { [weak self] in
            if let strongSelf = self {
                strongSelf.controllerInteraction.navigationController()?.pushViewController(installedStickerPacksController(account: account, mode: .modal))
            }
        }, toggleSearch: { [weak self] value in
            if let strongSelf = self {
                strongSelf.controllerInteraction.updateInputMode { current in
                    switch current {
                        case let .media(mode, _):
                            if value {
                                return .media(mode: mode, expanded: .search)
                            } else {
                                return .media(mode: mode, expanded: nil)
                            }
                        default:
                            return current
                    }
                }
            }
        }, openPeerSpecificSettings: { [weak self] in
            guard let peerId = peerId, peerId.namespace == Namespaces.Peer.CloudChannel else {
                return
            }
            
            let _ = (account.postbox.transaction { transaction -> StickerPackCollectionInfo? in
                return (transaction.getPeerCachedData(peerId: peerId) as? CachedChannelData)?.stickerPack
            }
            |> deliverOnMainQueue).start(next: { info in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.controllerInteraction.presentController(groupStickerPackSetupController(account: account, peerId: peerId, currentPackInfo: info), ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
            })
        }, dismissPeerSpecificSettings: { [weak self] in
            self?.dismissPeerSpecificPackSetup()
        })
        
        getItemIsPreviewedImpl = { [weak self] item in
            if let strongSelf = self {
                return strongSelf.inputNodeInteraction.previewedStickerPackItem == .pack(item)
            }
            return false
        }
        
        self.backgroundColor = theme.chat.inputMediaPanel.stickersBackgroundColor
        
        self.collectionListPanel.addSubnode(self.listView)
        self.collectionListContainer.addSubnode(self.collectionListPanel)
        self.collectionListContainer.addSubnode(self.collectionListSeparator)
        self.addSubnode(self.collectionListContainer)
        
        let itemCollectionsView = self.itemCollectionsViewPosition.get()
            |> distinctUntilChanged
            |> mapToSignal { position -> Signal<(ItemCollectionsView, StickerPacksCollectionUpdate), NoError> in
                switch position {
                    case .initial:
                        var firstTime = true
                        return account.postbox.itemCollectionsView(orderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudSavedStickers, Namespaces.OrderedItemList.CloudRecentStickers], namespaces: [Namespaces.ItemCollection.CloudStickerPacks], aroundIndex: nil, count: 50)
                            |> map { view -> (ItemCollectionsView, StickerPacksCollectionUpdate) in
                                let update: StickerPacksCollectionUpdate
                                if firstTime {
                                    firstTime = false
                                    update = .initial
                                } else {
                                    update = .generic
                                }
                                return (view, update)
                            }
                    case let .scroll(aroundIndex):
                        var firstTime = true
                        return account.postbox.itemCollectionsView(orderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudSavedStickers, Namespaces.OrderedItemList.CloudRecentStickers], namespaces: [Namespaces.ItemCollection.CloudStickerPacks], aroundIndex: aroundIndex, count: 300)
                            |> map { view -> (ItemCollectionsView, StickerPacksCollectionUpdate) in
                                let update: StickerPacksCollectionUpdate
                                if firstTime {
                                    firstTime = false
                                    update = .scroll
                                } else {
                                    update = .generic
                                }
                                return (view, update)
                            }
                    case let .navigate(index, collectionId):
                        var firstTime = true
                        return account.postbox.itemCollectionsView(orderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudSavedStickers, Namespaces.OrderedItemList.CloudRecentStickers], namespaces: [Namespaces.ItemCollection.CloudStickerPacks], aroundIndex: index, count: 300)
                            |> map { view -> (ItemCollectionsView, StickerPacksCollectionUpdate) in
                                let update: StickerPacksCollectionUpdate
                                if firstTime {
                                    firstTime = false
                                    update = .navigate(index, collectionId)
                                } else {
                                    update = .generic
                                }
                                return (view, update)
                        }
                }
        }
        
        let previousEntries = Atomic<([ChatMediaInputPanelEntry], [ChatMediaInputGridEntry])>(value: ([], []))
        
        let inputNodeInteraction = self.inputNodeInteraction!
        let peerSpecificPack: Signal<(PeerSpecificPackData?, CanInstallPeerSpecificPack), NoError>
        if let peerId = peerId {
            self.dismissedPeerSpecificStickerPack.set(account.postbox.transaction { transaction -> Bool in
                guard let state = transaction.getPeerChatInterfaceState(peerId) as? ChatInterfaceState else {
                    return false
                }
                if state.messageActionsState.closedPeerSpecificPackSetup {
                    return true
                }
                
                return false
            })
            peerSpecificPack = combineLatest(peerSpecificStickerPack(postbox: account.postbox, network: account.network, peerId: peerId), account.postbox.multiplePeersView([peerId]), self.dismissedPeerSpecificStickerPack.get())
            |> map { packData, peersView, dismissedPeerSpecificPack -> (PeerSpecificPackData?, CanInstallPeerSpecificPack) in
                if let peer = peersView.peers[peerId] {
                    var canInstall: CanInstallPeerSpecificPack = .none
                    if packData.canSetup {
                        canInstall = .available(dismissed: dismissedPeerSpecificPack)
                    }
                    if let (info, items) = packData.packInfo {
                        return (PeerSpecificPackData(peer: peer, info: info, items: items), canInstall)
                    } else {
                        return (nil, canInstall)
                    }
                }
                return (nil, .none)
            }
        } else {
            peerSpecificPack = .single((nil, .none))
        }
        
        let previousView = Atomic<ItemCollectionsView?>(value: nil)
        let transitions = combineLatest(itemCollectionsView, peerSpecificPack, self.themeAndStringsPromise.get())
        |> map { viewAndUpdate, peerSpecificPack, themeAndStrings -> (ItemCollectionsView, ChatMediaInputPanelTransition, Bool, ChatMediaInputGridTransition, Bool) in
            let (view, viewUpdate) = viewAndUpdate
            let previous = previousView.swap(view)
            var update = viewUpdate
            if previous === view {
                update = .generic
            }
            let (theme, strings) = themeAndStrings
            
            var savedStickers: OrderedItemListView?
            var recentStickers: OrderedItemListView?
            for orderedView in view.orderedItemListsViews {
                if orderedView.collectionId == Namespaces.OrderedItemList.CloudRecentStickers {
                    recentStickers = orderedView
                } else if orderedView.collectionId == Namespaces.OrderedItemList.CloudSavedStickers {
                    savedStickers = orderedView
                }
            }
            let panelEntries = chatMediaInputPanelEntries(view: view, savedStickers: savedStickers, recentStickers: recentStickers, peerSpecificPack: peerSpecificPack.0, theme: theme)
            let gridEntries = chatMediaInputGridEntries(view: view, savedStickers: savedStickers, recentStickers: recentStickers, peerSpecificPack: peerSpecificPack.0, canInstallPeerSpecificPack: peerSpecificPack.1, strings: strings, theme: theme)
            let (previousPanelEntries, previousGridEntries) = previousEntries.swap((panelEntries, gridEntries))
            return (view, preparedChatMediaInputPanelEntryTransition(account: account, from: previousPanelEntries, to: panelEntries, inputNodeInteraction: inputNodeInteraction), previousPanelEntries.isEmpty, preparedChatMediaInputGridEntryTransition(account: account, view: view, from: previousGridEntries, to: gridEntries, update: update, interfaceInteraction: controllerInteraction, inputNodeInteraction: inputNodeInteraction), previousGridEntries.isEmpty)
        }
        
        self.disposable.set((transitions
        |> deliverOnMainQueue).start(next: { [weak self] (view, panelTransition, panelFirstTime, gridTransition, gridFirstTime) in
            if let strongSelf = self {
                strongSelf.currentView = view
                strongSelf.enqueuePanelTransition(panelTransition, firstTime: panelFirstTime, thenGridTransition: gridTransition, gridFirstTime: gridFirstTime)
                if !strongSelf.initializedArrangement {
                    strongSelf.initializedArrangement = true
                    var currentPane = strongSelf.paneArrangement.panes[strongSelf.paneArrangement.currentIndex]
                    if view.entries.isEmpty {
                        currentPane = .trending
                    }
                    if currentPane != strongSelf.paneArrangement.panes[strongSelf.paneArrangement.currentIndex] {
                        strongSelf.setCurrentPane(currentPane, transition: .immediate)
                    }
                }
            }
        }))
        
        self.stickerPane.gridNode.visibleItemsUpdated = { [weak self] visibleItems in
            if let strongSelf = self {
                var topVisibleCollectionId: ItemCollectionId?
                
                if let topVisibleSection = visibleItems.topSectionVisible as? ChatMediaInputStickerGridSection {
                    topVisibleCollectionId = topVisibleSection.collectionId
                } else if let topVisible = visibleItems.topVisible, let item = topVisible.1 as? ChatMediaInputStickerGridItem {
                    topVisibleCollectionId = item.index.collectionId
                }
                if let collectionId = topVisibleCollectionId {
                    if strongSelf.inputNodeInteraction.highlightedItemCollectionId != collectionId {
                        strongSelf.setHighlightedItemCollectionId(collectionId)
                    }
                }
                
                if let currentView = strongSelf.currentView, let (topIndex, topItem) = visibleItems.top, let (bottomIndex, bottomItem) = visibleItems.bottom {
                    if topIndex <= 10 && currentView.lower != nil {
                        let position: StickerPacksCollectionPosition = clipScrollPosition(.scroll(aroundIndex: (topItem as! ChatMediaInputStickerGridItem).index))
                        if strongSelf.currentStickerPacksCollectionPosition != position {
                            strongSelf.currentStickerPacksCollectionPosition = position
                            strongSelf.itemCollectionsViewPosition.set(.single(position))
                        }
                    } else if bottomIndex >= visibleItems.count - 10 && currentView.higher != nil {
                        var position: StickerPacksCollectionPosition?
                        if let bottomItem = bottomItem as? ChatMediaInputStickerGridItem {
                            position = clipScrollPosition(.scroll(aroundIndex: bottomItem.index))
                        }
                        
                        if let position = position, strongSelf.currentStickerPacksCollectionPosition != position {
                            strongSelf.currentStickerPacksCollectionPosition = position
                            strongSelf.itemCollectionsViewPosition.set(.single(position))
                        }
                    }
                }
            }
        }
        
        self.currentStickerPacksCollectionPosition = .initial
        self.itemCollectionsViewPosition.set(.single(.initial))
        
        paneDidScrollImpl = { [weak self] pane, state, transition in
            self?.updatePaneDidScroll(pane: pane, state: state, transition: transition)
        }
        
        fixPaneScrollImpl = { [weak self] pane, state in
            self?.fixPaneScroll(pane: pane, state: state)
        }
    }
    
    deinit {
        self.disposable.dispose()
    }
    
    private func updateThemeAndStrings(theme: PresentationTheme, strings: PresentationStrings) {
        if self.theme !== theme || self.strings !== strings {
            self.theme = theme
            self.strings = strings
            
            self.collectionListPanel.backgroundColor = theme.chat.inputPanel.panelBackgroundColor
            self.collectionListSeparator.backgroundColor = theme.chat.inputMediaPanel.panelSerapatorColor
            self.backgroundColor = theme.chat.inputMediaPanel.gifsBackgroundColor
            
            self.themeAndStringsPromise.set(.single((theme, strings)))
        }
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.view.disablesInteractiveTransitionGestureRecognizer = true
        self.view.addGestureRecognizer(PeekControllerGestureRecognizer(contentAtPoint: { [weak self] point in
            if let strongSelf = self {
                let panes: [ASDisplayNode]
                if let stickerSearchContainerNode = strongSelf.stickerSearchContainerNode {
                    panes = []
                    if let (itemNode, item) = stickerSearchContainerNode.itemAt(point: point.offsetBy(dx: -stickerSearchContainerNode.frame.minX, dy: -stickerSearchContainerNode.frame.minY)) {
                        return strongSelf.account.postbox.transaction { transaction -> Bool in
                            return getIsStickerSaved(transaction: transaction, fileId: item.file.fileId)
                            }
                            |> deliverOnMainQueue
                            |> map { isStarred -> (ASDisplayNode, PeekControllerContent)? in
                                if let strongSelf = self {
                                    var menuItems: [PeekControllerMenuItem] = []
                                    menuItems = [
                                        PeekControllerMenuItem(title: strongSelf.strings.ShareMenu_Send, color: .accent, font: .bold, action: {
                                            if let strongSelf = self {
                                                strongSelf.controllerInteraction.sendSticker(.standalone(media: item.file))
                                            }
                                        }),
                                        PeekControllerMenuItem(title: isStarred ? strongSelf.strings.Stickers_RemoveFromFavorites : strongSelf.strings.Stickers_AddToFavorites, color: isStarred ? .destructive : .accent, action: {
                                            if let strongSelf = self {
                                                if isStarred {
                                                    let _ = removeSavedSticker(postbox: strongSelf.account.postbox, mediaId: item.file.fileId).start()
                                                } else {
                                                    let _ = addSavedSticker(postbox: strongSelf.account.postbox, network: strongSelf.account.network, file: item.file).start()
                                                }
                                            }
                                        }),
                                        PeekControllerMenuItem(title: strongSelf.strings.StickerPack_ViewPack, color: .accent, action: {
                                            if let strongSelf = self {
                                                loop: for attribute in item.file.attributes {
                                                    switch attribute {
                                                    case let .Sticker(_, packReference, _):
                                                        if let packReference = packReference {
                                                            let controller = StickerPackPreviewController(account: strongSelf.account, stickerPack: packReference, parentNavigationController: strongSelf.controllerInteraction.navigationController())
                                                            controller.sendSticker = { file in
                                                                if let strongSelf = self {
                                                                    strongSelf.controllerInteraction.sendSticker(file)
                                                                }
                                                            }
                                                            
                                                            strongSelf.controllerInteraction.navigationController()?.view.window?.endEditing(true)
                                                            strongSelf.controllerInteraction.presentController(controller, nil)
                                                        }
                                                        break loop
                                                    default:
                                                        break
                                                    }
                                                }
                                            }
                                        }),
                                        PeekControllerMenuItem(title: strongSelf.strings.Common_Cancel, color: .accent, action: {})
                                    ]
                                    return (itemNode, StickerPreviewPeekContent(account: strongSelf.account, item: item, menu: menuItems))
                                } else {
                                    return nil
                                }
                        }
                    }
                } else {
                    panes = [strongSelf.gifPane, strongSelf.stickerPane, strongSelf.trendingPane]
                }
                for pane in panes {
                    if pane.supernode != nil, pane.frame.contains(point) {
                        if let pane = pane as? ChatMediaInputGifPane {
                            if let file = pane.fileAt(point: point.offsetBy(dx: -pane.frame.minX, dy: -pane.frame.minY)) {
                                return .single((strongSelf, ChatContextResultPeekContent(account: strongSelf.account, contextResult: .internalReference(queryId: 0, id: "", type: "gif", title: nil, description: nil, image: nil, file: file.media, message: .auto(caption: "", entities: nil, replyMarkup: nil)), menu: [
                                    PeekControllerMenuItem(title: strongSelf.strings.ShareMenu_Send, color: .accent, font: .bold, action: {
                                        if let strongSelf = self {
                                            strongSelf.controllerInteraction.sendGif(file)
                                        }
                                    }),
                                    PeekControllerMenuItem(title: strongSelf.strings.Common_Delete, color: .destructive, action: {
                                        if let strongSelf = self {
                                            let _ = removeSavedGif(postbox: strongSelf.account.postbox, mediaId: file.media.fileId).start()
                                        }
                                    })
                                ])))
                            }
                        } else if pane is ChatMediaInputStickerPane || pane is ChatMediaInputTrendingPane {
                            var itemNodeAndItem: (ASDisplayNode, StickerPackItem)?
                            if let pane = pane as? ChatMediaInputStickerPane {
                                itemNodeAndItem = pane.itemAt(point: point.offsetBy(dx: -pane.frame.minX, dy: -pane.frame.minY))
                            } else if let pane = pane as? ChatMediaInputTrendingPane {
                                itemNodeAndItem = pane.itemAt(point: point.offsetBy(dx: -pane.frame.minX, dy: -pane.frame.minY))
                            }
                            
                            if let (itemNode, item) = itemNodeAndItem {
                                return strongSelf.account.postbox.transaction { transaction -> Bool in
                                    return getIsStickerSaved(transaction: transaction, fileId: item.file.fileId)
                                }
                                |> deliverOnMainQueue
                                |> map { isStarred -> (ASDisplayNode, PeekControllerContent)? in
                                    if let strongSelf = self {
                                        var menuItems: [PeekControllerMenuItem] = []
                                        menuItems = [
                                            PeekControllerMenuItem(title: strongSelf.strings.ShareMenu_Send, color: .accent, font: .bold, action: {
                                                if let strongSelf = self {
                                                    strongSelf.controllerInteraction.sendSticker(.standalone(media: item.file))
                                                }
                                            }),
                                            PeekControllerMenuItem(title: isStarred ? strongSelf.strings.Stickers_RemoveFromFavorites : strongSelf.strings.Stickers_AddToFavorites, color: isStarred ? .destructive : .accent, action: {
                                                if let strongSelf = self {
                                                    if isStarred {
                                                        let _ = removeSavedSticker(postbox: strongSelf.account.postbox, mediaId: item.file.fileId).start()
                                                    } else {
                                                        let _ = addSavedSticker(postbox: strongSelf.account.postbox, network: strongSelf.account.network, file: item.file).start()
                                                    }
                                                }
                                            }),
                                            PeekControllerMenuItem(title: strongSelf.strings.StickerPack_ViewPack, color: .accent, action: {
                                                if let strongSelf = self {
                                                    loop: for attribute in item.file.attributes {
                                                        switch attribute {
                                                            case let .Sticker(_, packReference, _):
                                                                if let packReference = packReference {
                                                                    let controller = StickerPackPreviewController(account: strongSelf.account, stickerPack: packReference, parentNavigationController: strongSelf.controllerInteraction.navigationController())
                                                                    controller.sendSticker = { file in
                                                                        if let strongSelf = self {
                                                                            strongSelf.controllerInteraction.sendSticker(file)
                                                                        }
                                                                    }
                                                          
                                                                    strongSelf.controllerInteraction.navigationController()?.view.window?.endEditing(true)
                                                                    strongSelf.controllerInteraction.presentController(controller, nil)
                                                                }
                                                                break loop
                                                            default:
                                                                break
                                                        }
                                                    }
                                                }
                                            }),
                                            PeekControllerMenuItem(title: strongSelf.strings.Common_Cancel, color: .accent, action: {})
                                        ]
                                        return (itemNode, StickerPreviewPeekContent(account: strongSelf.account, item: .pack(item), menu: menuItems))
                                    } else {
                                        return nil
                                    }
                                }
                            }
                        }
                    }
                }
            }
            return nil
        }, present: { [weak self] content, sourceNode in
            if let strongSelf = self {
                let controller = PeekController(theme: PeekControllerTheme(presentationTheme: strongSelf.theme), content: content, sourceNode: {
                    return sourceNode
                })
                strongSelf.controllerInteraction.presentGlobalOverlayController(controller, nil)
                return controller
            }
            return nil
        }, updateContent: { [weak self] content in
            if let strongSelf = self {
                var item: StickerPreviewPeekItem?
                if let content = content as? StickerPreviewPeekContent {
                    item = content.item
                }
                strongSelf.updatePreviewingItem(item: item, animated: true)
            }
        }))
        let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(self.panGesture(_:)))
        self.panRecognizer = panRecognizer
        self.view.addGestureRecognizer(panRecognizer)
    }
    
    private func setCurrentPane(_ pane: ChatMediaInputPaneType, transition: ContainedViewLayoutTransition) {
        if let index = self.paneArrangement.panes.index(of: pane), index != self.paneArrangement.currentIndex {
            let previousGifPanelWasActive = self.paneArrangement.panes[self.paneArrangement.currentIndex] == .gifs
            self.paneArrangement = self.paneArrangement.withIndexTransition(0.0).withCurrentIndex(index)
            if let (width, leftInset, rightInset, bottomInset, standardInputHeight, inputHeight, maximumHeight, inputPanelHeight, interfaceState) = self.validLayout {
                let _ = self.updateLayout(width: width, leftInset: leftInset, rightInset: rightInset, bottomInset: bottomInset, standardInputHeight: standardInputHeight, inputHeight: inputHeight, maximumHeight: maximumHeight, inputPanelHeight: inputPanelHeight,  transition: .animated(duration: 0.25, curve: .spring), interfaceState: interfaceState)
                self.updateAppearanceTransition(transition: transition)
            }
            let updatedGifPanelWasActive = self.paneArrangement.panes[self.paneArrangement.currentIndex] == .gifs
            if updatedGifPanelWasActive != previousGifPanelWasActive {
                self.gifPaneIsActiveUpdated(updatedGifPanelWasActive)
            }
            switch pane {
                case .gifs:
                    self.setHighlightedItemCollectionId(ItemCollectionId(namespace: ChatMediaInputPanelAuxiliaryNamespace.recentGifs.rawValue, id: 0))
                case .stickers:
                    if let highlightedStickerCollectionId = self.inputNodeInteraction.highlightedStickerItemCollectionId {
                        self.setHighlightedItemCollectionId(highlightedStickerCollectionId)
                    }
                case .trending:
                    self.setHighlightedItemCollectionId(ItemCollectionId(namespace: ChatMediaInputPanelAuxiliaryNamespace.trending.rawValue, id: 0))
            }
        } else {
            if let (width, leftInset, rightInset, bottomInset, standardInputHeight, inputHeight, maximumHeight, inputPanelHeight, interfaceState) = self.validLayout {
                let _ = self.updateLayout(width: width, leftInset: leftInset, rightInset: rightInset, bottomInset: bottomInset, standardInputHeight: standardInputHeight, inputHeight: inputHeight, maximumHeight: maximumHeight, inputPanelHeight: inputPanelHeight, transition: .animated(duration: 0.25, curve: .spring), interfaceState: interfaceState)
            }
        }
    }
    
    private func setHighlightedItemCollectionId(_ collectionId: ItemCollectionId) {
        if collectionId.namespace == ChatMediaInputPanelAuxiliaryNamespace.recentGifs.rawValue {
            if self.paneArrangement.panes[self.paneArrangement.currentIndex] == .gifs {
                self.inputNodeInteraction.highlightedItemCollectionId = collectionId
            }
        } else if collectionId.namespace == ChatMediaInputPanelAuxiliaryNamespace.trending.rawValue {
            if self.paneArrangement.panes[self.paneArrangement.currentIndex] == .trending {
                self.inputNodeInteraction.highlightedItemCollectionId = collectionId
            }
        } else {
            self.inputNodeInteraction.highlightedStickerItemCollectionId = collectionId
            if self.paneArrangement.panes[self.paneArrangement.currentIndex] == .stickers {
                self.inputNodeInteraction.highlightedItemCollectionId = collectionId
            }
        }
        var ensuredNodeVisible = false
        var firstVisibleCollectionId: ItemCollectionId?
        self.listView.forEachItemNode { itemNode in
            if let itemNode = itemNode as? ChatMediaInputStickerPackItemNode {
                if firstVisibleCollectionId == nil {
                    firstVisibleCollectionId = itemNode.currentCollectionId
                }
                itemNode.updateIsHighlighted()
                if itemNode.currentCollectionId == collectionId {
                    self.listView.ensureItemNodeVisible(itemNode)
                    ensuredNodeVisible = true
                }
            } else if let itemNode = itemNode as? ChatMediaInputMetaSectionItemNode {
                itemNode.updateIsHighlighted()
                if itemNode.currentCollectionId == collectionId {
                    self.listView.ensureItemNodeVisible(itemNode)
                    ensuredNodeVisible = true
                }
            } else if let itemNode = itemNode as? ChatMediaInputRecentGifsItemNode {
                itemNode.updateIsHighlighted()
                if itemNode.currentCollectionId == collectionId {
                    self.listView.ensureItemNodeVisible(itemNode)
                    ensuredNodeVisible = true
                }
            } else if let itemNode = itemNode as? ChatMediaInputTrendingItemNode {
                itemNode.updateIsHighlighted()
                if itemNode.currentCollectionId == collectionId {
                    self.listView.ensureItemNodeVisible(itemNode)
                    ensuredNodeVisible = true
                }
            } else if let itemNode = itemNode as? ChatMediaInputPeerSpecificItemNode {
                itemNode.updateIsHighlighted()
                if itemNode.currentCollectionId == collectionId {
                    self.listView.ensureItemNodeVisible(itemNode)
                    ensuredNodeVisible = true
                }
            }
        }
        
        if let currentView = self.currentView, let firstVisibleCollectionId = firstVisibleCollectionId, !ensuredNodeVisible {
            let targetIndex = currentView.collectionInfos.index(where: { id, _, _ in return id == collectionId })
            let firstVisibleIndex = currentView.collectionInfos.index(where: { id, _, _ in return id == firstVisibleCollectionId })
            if let targetIndex = targetIndex, let firstVisibleIndex = firstVisibleIndex {
                let toRight = targetIndex > firstVisibleIndex
                self.listView.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [], scrollToItem: ListViewScrollToItem(index: targetIndex, position: toRight ? .bottom(0.0) : .top(0.0), animated: true, curve: .Default, directionHint: toRight ? .Down : .Up), updateSizeAndInsets: nil, stationaryItemRange: nil, updateOpaqueState: nil)
            }
        }
    }
    
    private func currentCollectionListPanelOffset() -> CGFloat {
        let paneOffsets = self.paneArrangement.panes.map { pane -> CGFloat in
            switch pane {
                case .stickers:
                    return self.stickerPane.collectionListPanelOffset
                case .gifs:
                    return self.gifPane.collectionListPanelOffset
                case .trending:
                    return self.trendingPane.collectionListPanelOffset
            }
        }
        
        let mainOffset = paneOffsets[self.paneArrangement.currentIndex]
        if self.paneArrangement.indexTransition.isZero {
            return mainOffset
        } else {
            var sideOffset: CGFloat?
            if self.paneArrangement.indexTransition < 0.0 {
                if self.paneArrangement.currentIndex != 0 {
                    sideOffset = paneOffsets[self.paneArrangement.currentIndex - 1]
                }
            } else {
                if self.paneArrangement.currentIndex != paneOffsets.count - 1 {
                    sideOffset = paneOffsets[self.paneArrangement.currentIndex + 1]
                }
            }
            if let sideOffset = sideOffset {
                let interpolator = CGFloat.interpolator()
                let value = interpolator(mainOffset, sideOffset, abs(self.paneArrangement.indexTransition)) as! CGFloat
                return value
            } else {
                return mainOffset
            }
        }
    }
    
    private func updateAppearanceTransition(transition: ContainedViewLayoutTransition) {
        var value: CGFloat = 1.0 - abs(self.currentCollectionListPanelOffset() / 41.0)
        value = min(1.0, max(0.0, value))
        self.inputNodeInteraction.appearanceTransition = max(0.1, value)
        transition.updateAlpha(node: self.listView, alpha: value)
        self.listView.forEachItemNode { itemNode in
            if let itemNode = itemNode as? ChatMediaInputStickerPackItemNode {
                itemNode.updateAppearanceTransition(transition: transition)
            } else if let itemNode = itemNode as? ChatMediaInputMetaSectionItemNode {
                itemNode.updateAppearanceTransition(transition: transition)
            } else if let itemNode = itemNode as? ChatMediaInputRecentGifsItemNode {
                itemNode.updateAppearanceTransition(transition: transition)
            } else if let itemNode = itemNode as? ChatMediaInputTrendingItemNode {
                itemNode.updateAppearanceTransition(transition: transition)
            } else if let itemNode = itemNode as? ChatMediaInputPeerSpecificItemNode {
                itemNode.updateAppearanceTransition(transition: transition)
            }
        }
    }
    
    override func updateLayout(width: CGFloat, leftInset: CGFloat, rightInset: CGFloat, bottomInset: CGFloat, standardInputHeight: CGFloat, inputHeight: CGFloat, maximumHeight: CGFloat, inputPanelHeight: CGFloat, transition: ContainedViewLayoutTransition, interfaceState: ChatPresentationInterfaceState) -> (CGFloat, CGFloat) {
        self.validLayout = (width, leftInset, rightInset, bottomInset, standardInputHeight, inputHeight, maximumHeight, inputPanelHeight, interfaceState)
        
        if self.theme !== interfaceState.theme || self.strings !== interfaceState.strings {
            self.updateThemeAndStrings(theme: interfaceState.theme, strings: interfaceState.strings)
        }
        
        var displaySearch = false
        
        let separatorHeight = UIScreenPixel
        let panelHeight: CGFloat
        var isExpanded: Bool = false
        if case let .media(_, maybeExpanded) = interfaceState.inputMode, let expanded = maybeExpanded {
            isExpanded = true
            switch expanded {
                case .content:
                    panelHeight = maximumHeight
                case .search:
                    panelHeight = maximumHeight
                    displaySearch = true
            }
        } else {
            panelHeight = standardInputHeight
        }
        
        if displaySearch {
            let containerFrame = CGRect(origin: CGPoint(x: 0.0, y: -inputPanelHeight), size: CGSize(width: width, height: panelHeight + inputPanelHeight))
            if let stickerSearchContainerNode = self.stickerSearchContainerNode {
                transition.updateFrame(node: stickerSearchContainerNode, frame: containerFrame)
                stickerSearchContainerNode.updateLayout(size: containerFrame.size, leftInset: leftInset, rightInset: rightInset, bottomInset: bottomInset, inputHeight: inputHeight, transition: transition)
            } else {
                let stickerSearchContainerNode = StickerPaneSearchContainerNode(account: self.account, theme: self.theme, strings: self.strings, controllerInteraction: self.controllerInteraction, inputNodeInteraction: self.inputNodeInteraction, cancel: { [weak self] in
                    self?.stickerSearchContainerNode?.deactivate()
                    self?.inputNodeInteraction.toggleSearch(false)
                })
                self.stickerSearchContainerNode = stickerSearchContainerNode
                self.insertSubnode(stickerSearchContainerNode, belowSubnode: self.collectionListContainer)
                stickerSearchContainerNode.frame = containerFrame
                stickerSearchContainerNode.updateLayout(size: containerFrame.size, leftInset: leftInset, rightInset: rightInset, bottomInset: bottomInset, inputHeight: inputHeight, transition: .immediate)
                var placeholderNode: StickerPaneSearchBarPlaceholderNode?
                self.stickerPane.gridNode.forEachItemNode { itemNode in
                    if let itemNode = itemNode as? StickerPaneSearchBarPlaceholderNode {
                        placeholderNode = itemNode
                    }
                }
                if let placeholderNode = placeholderNode {
                    stickerSearchContainerNode.animateIn(from: placeholderNode, transition: transition)
                }
            }
        }
        
        let contentVerticalOffset: CGFloat = displaySearch ? -(inputPanelHeight + 41.0) : 0.0
        
        let collectionListPanelOffset = self.currentCollectionListPanelOffset()
        
        transition.updateFrame(node: self.collectionListContainer, frame: CGRect(origin: CGPoint(x: 0.0, y: contentVerticalOffset), size: CGSize(width: width, height: max(0.0, 41.0 + UIScreenPixel))))
        transition.updateFrame(node: self.collectionListPanel, frame: CGRect(origin: CGPoint(x: 0.0, y: collectionListPanelOffset), size: CGSize(width: width, height: 41.0)))
        transition.updateFrame(node: self.collectionListSeparator, frame: CGRect(origin: CGPoint(x: 0.0, y: 41.0 + collectionListPanelOffset), size: CGSize(width: width, height: separatorHeight)))
        
        self.listView.bounds = CGRect(x: 0.0, y: 0.0, width: 41.0, height: width)
        transition.updatePosition(node: self.listView, position: CGPoint(x: width / 2.0, y: (41.0 - collectionListPanelOffset) / 2.0))
        
        var duration: Double = 0.0
        var curve: UInt = 0
        switch transition {
            case .immediate:
                break
            case let .animated(animationDuration, animationCurve):
                duration = animationDuration
                switch animationCurve {
                    case .easeInOut:
                        break
                    case .spring:
                        curve = 7
                }
        }
        
        let listViewCurve: ListViewAnimationCurve
        if curve == 7 {
            listViewCurve = .Spring(duration: duration)
        } else {
            listViewCurve = .Default
        }
        
        let updateSizeAndInsets = ListViewUpdateSizeAndInsets(size: CGSize(width: 41.0, height: width), insets: UIEdgeInsets(top: 4.0 + leftInset, left: 0.0, bottom: 4.0 + rightInset, right: 0.0), duration: duration, curve: listViewCurve)
        
        self.listView.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: nil, updateSizeAndInsets: updateSizeAndInsets, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
        
        var visiblePanes: [(ChatMediaInputPaneType, CGFloat)] = []
        
        var paneIndex = 0
        for pane in self.paneArrangement.panes {
            let paneOrigin = CGFloat(paneIndex - self.paneArrangement.currentIndex) * width - self.paneArrangement.indexTransition * width
            if paneOrigin.isLess(than: width) && CGFloat(0.0).isLess(than: (paneOrigin + width)) {
                visiblePanes.append((pane, paneOrigin))
            }
            paneIndex += 1
        }
        
        for (pane, paneOrigin) in visiblePanes {
            let paneFrame = CGRect(origin: CGPoint(x: paneOrigin + leftInset, y: 0.0), size: CGSize(width: width - leftInset - rightInset, height: panelHeight))
            switch pane {
                case .gifs:
                    if self.gifPane.supernode == nil {
                        self.insertSubnode(self.gifPane, belowSubnode: self.collectionListContainer)
                        self.gifPane.frame = CGRect(origin: CGPoint(x: -width, y: 0.0), size: CGSize(width: width, height: panelHeight))
                    }
                    if self.gifPane.frame != paneFrame {
                        self.gifPane.layer.removeAnimation(forKey: "position")
                        transition.updateFrame(node: self.gifPane, frame: paneFrame)
                    }
                case .stickers:
                    if self.stickerPane.supernode == nil {
                        self.insertSubnode(self.stickerPane, belowSubnode: self.collectionListContainer)
                        self.stickerPane.frame = CGRect(origin: CGPoint(x: width, y: 0.0), size: CGSize(width: width, height: panelHeight))
                    }
                    if self.stickerPane.frame != paneFrame {
                        self.stickerPane.layer.removeAnimation(forKey: "position")
                        transition.updateFrame(node: self.stickerPane, frame: paneFrame)
                    }
                case .trending:
                    if self.trendingPane.supernode == nil {
                        self.insertSubnode(self.trendingPane, belowSubnode: self.collectionListContainer)
                        self.trendingPane.frame = CGRect(origin: CGPoint(x: width, y: 0.0), size: CGSize(width: width, height: panelHeight))
                    }
                    if self.trendingPane.frame != paneFrame {
                        self.trendingPane.layer.removeAnimation(forKey: "position")
                        transition.updateFrame(node: self.trendingPane, frame: paneFrame)
                    }
            }
        }
        
        self.gifPane.updateLayout(size: CGSize(width: width - leftInset - rightInset, height: panelHeight), topInset: 41.0, bottomInset: bottomInset, isExpanded: isExpanded, transition: transition)
        
        self.stickerPane.updateLayout(size: CGSize(width: width - leftInset - rightInset, height: panelHeight), topInset: 41.0, bottomInset: bottomInset, isExpanded: isExpanded, transition: transition)
        self.trendingPane.updateLayout(size: CGSize(width: width - leftInset - rightInset, height: panelHeight), topInset: 41.0, bottomInset: bottomInset, isExpanded: isExpanded, transition: transition)
        
        if self.gifPane.supernode != nil {
            if !visiblePanes.contains(where: { $0.0 == .gifs }) {
                if case .animated = transition {
                    if !self.animatingGifPaneOut {
                        self.animatingGifPaneOut = true
                        var toLeft = false
                        if let index = self.paneArrangement.panes.index(of: .gifs), index < self.paneArrangement.currentIndex {
                            toLeft = true
                        }
                        transition.animatePosition(node: self.gifPane, to: CGPoint(x: (toLeft ? -width : width) + width / 2.0, y: self.gifPane.layer.position.y), removeOnCompletion: false, completion: { [weak self] value in
                            if let strongSelf = self, value {
                                strongSelf.animatingGifPaneOut = false
                                strongSelf.gifPane.removeFromSupernode()
                            }
                        })
                    }
                } else {
                    self.animatingGifPaneOut = false
                    self.gifPane.removeFromSupernode()
                }
            }
        } else {
            self.animatingGifPaneOut = false
        }
        
        if self.stickerPane.supernode != nil {
            if !visiblePanes.contains(where: { $0.0 == .stickers }) {
                if case .animated = transition {
                    if !self.animatingStickerPaneOut {
                        self.animatingStickerPaneOut = true
                        var toLeft = false
                        if let index = self.paneArrangement.panes.index(of: .stickers), index < self.paneArrangement.currentIndex {
                            toLeft = true
                        }
                        transition.animatePosition(node: self.stickerPane, to: CGPoint(x: (toLeft ? -width : width) + width / 2.0, y: self.stickerPane.layer.position.y), removeOnCompletion: false, completion: { [weak self] value in
                            if let strongSelf = self, value {
                                strongSelf.animatingStickerPaneOut = false
                                strongSelf.stickerPane.removeFromSupernode()
                            }
                        })
                    }
                } else {
                    self.animatingStickerPaneOut = false
                    self.stickerPane.removeFromSupernode()
                }
            }
        } else {
            self.animatingStickerPaneOut = false
        }
        
        if self.trendingPane.supernode != nil {
            if !visiblePanes.contains(where: { $0.0 == .trending }) {
                if case .animated = transition {
                    if !self.animatingTrendingPaneOut {
                        self.animatingTrendingPaneOut = true
                        var toLeft = false
                        if let index = self.paneArrangement.panes.index(of: .trending), index < self.paneArrangement.currentIndex {
                            toLeft = true
                        }
                        transition.animatePosition(node: self.trendingPane, to: CGPoint(x: (toLeft ? -width : width) + width / 2.0, y: self.trendingPane.layer.position.y), removeOnCompletion: false, completion: { [weak self] value in
                            if let strongSelf = self, value {
                                strongSelf.animatingTrendingPaneOut = false
                                strongSelf.trendingPane.removeFromSupernode()
                            }
                        })
                    }
                } else {
                    self.animatingTrendingPaneOut = false
                    self.trendingPane.removeFromSupernode()
                }
            }
        } else {
            self.animatingTrendingPaneOut = false
        }
        
        if !displaySearch, let stickerSearchContainerNode = self.stickerSearchContainerNode {
            self.stickerSearchContainerNode = nil
            
            var placeholderNode: StickerPaneSearchBarPlaceholderNode?
            self.stickerPane.gridNode.forEachItemNode { itemNode in
                if let itemNode = itemNode as? StickerPaneSearchBarPlaceholderNode {
                    placeholderNode = itemNode
                }
            }
            if let placeholderNode = placeholderNode {
                stickerSearchContainerNode.animateOut(to: placeholderNode, transition: transition, completion: { [weak stickerSearchContainerNode] in
                    stickerSearchContainerNode?.removeFromSupernode()
                })
            } else {
                stickerSearchContainerNode.removeFromSupernode()
            }
        }
        
        if let panRecognizer = self.panRecognizer, panRecognizer.isEnabled != !displaySearch {
            panRecognizer.isEnabled = !displaySearch
        }
        
        return (standardInputHeight, max(0.0, panelHeight - standardInputHeight))
    }
    
    private func enqueuePanelTransition(_ transition: ChatMediaInputPanelTransition, firstTime: Bool, thenGridTransition gridTransition: ChatMediaInputGridTransition, gridFirstTime: Bool) {
        var options = ListViewDeleteAndInsertOptions()
        if firstTime {
            options.insert(.Synchronous)
            options.insert(.LowLatency)
        } else {
            options.insert(.AnimateInsertion)
        }
        self.listView.transaction(deleteIndices: transition.deletions, insertIndicesAndItems: transition.insertions, updateIndicesAndItems: transition.updates, options: options, updateOpaqueState: nil, completion: { [weak self] _ in
            if let strongSelf = self {
                strongSelf.enqueueGridTransition(gridTransition, firstTime: gridFirstTime)
            }
        })
    }
    
    private func enqueueGridTransition(_ transition: ChatMediaInputGridTransition, firstTime: Bool) {
        var itemTransition: ContainedViewLayoutTransition = .immediate
        if transition.animated {
            itemTransition = .animated(duration: 0.3, curve: .spring)
        }
        self.stickerPane.gridNode.transaction(GridNodeTransaction(deleteItems: transition.deletions, insertItems: transition.insertions, updateItems: transition.updates, scrollToItem: transition.scrollToItem, updateLayout: nil, itemTransition: itemTransition, stationaryItems: transition.stationaryItems, updateFirstIndexInSectionOffset: transition.updateFirstIndexInSectionOffset, updateOpaqueState: transition.updateOpaqueState), completion: { _ in })
    }
    
    private func updatePreviewingItem(item: StickerPreviewPeekItem?, animated: Bool) {
        if self.inputNodeInteraction.previewedStickerPackItem != item {
            self.inputNodeInteraction.previewedStickerPackItem = item
            
            self.stickerPane.gridNode.forEachItemNode { itemNode in
                if let itemNode = itemNode as? ChatMediaInputStickerGridItemNode {
                    itemNode.updatePreviewing(animated: animated)
                }
            }
            
            self.stickerSearchContainerNode?.updatePreviewing(animated: animated)
            self.trendingPane.updatePreviewing(animated: animated)
        }
    }
    
    @objc func panGesture(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
            case .began:
                if self.animatingGifPaneOut {
                    self.animatingGifPaneOut = false
                    self.gifPane.removeFromSupernode()
                }
                self.gifPane.layer.removeAllAnimations()
                self.stickerPane.layer.removeAllAnimations()
                if self.animatingStickerPaneOut {
                    self.animatingStickerPaneOut = false
                    self.stickerPane.removeFromSupernode()
                }
                self.trendingPane.layer.removeAllAnimations()
                if self.animatingTrendingPaneOut {
                    self.animatingTrendingPaneOut = false
                    self.trendingPane.removeFromSupernode()
            }
            case .changed:
                if let (width, leftInset, rightInset, bottomInset, standardInputHeight, inputHeight, maximumHeight, inputPanelHeight, interfaceState) = self.validLayout {
                    let translationX = -recognizer.translation(in: self.view).x
                    var indexTransition = translationX / width
                    if self.paneArrangement.currentIndex == 0 {
                        indexTransition = max(0.0, indexTransition)
                    } else if self.paneArrangement.currentIndex == self.paneArrangement.panes.count - 1 {
                        indexTransition = min(0.0, indexTransition)
                    }
                    self.paneArrangement = self.paneArrangement.withIndexTransition(indexTransition)
                    let _ = self.updateLayout(width: width, leftInset: leftInset, rightInset: rightInset, bottomInset: bottomInset, standardInputHeight: standardInputHeight, inputHeight: inputHeight, maximumHeight: maximumHeight, inputPanelHeight: inputPanelHeight, transition: .immediate, interfaceState: interfaceState)
                }
            case .ended:
                if let (width, _, _, _, _, _, _, _, _) = self.validLayout {
                    var updatedIndex = self.paneArrangement.currentIndex
                    if abs(self.paneArrangement.indexTransition * width) > 30.0 {
                        if self.paneArrangement.indexTransition < 0.0 {
                            updatedIndex = max(0, self.paneArrangement.currentIndex - 1)
                        } else {
                            updatedIndex = min(self.paneArrangement.panes.count - 1, self.paneArrangement.currentIndex + 1)
                        }
                    }
                    self.paneArrangement = self.paneArrangement.withIndexTransition(0.0)
                    self.setCurrentPane(self.paneArrangement.panes[updatedIndex], transition: .animated(duration: 0.25, curve: .spring))
                }
            case .cancelled:
                if let (width, leftInset, rightInset, bottomInset, standardInputHeight, inputHeight, maximumHeight, inputPanelHeight, interfaceState) = self.validLayout {
                    self.paneArrangement = self.paneArrangement.withIndexTransition(0.0)
                    let _ = self.updateLayout(width: width, leftInset: leftInset, rightInset: rightInset, bottomInset: bottomInset, standardInputHeight: standardInputHeight, inputHeight: inputHeight, maximumHeight: maximumHeight, inputPanelHeight: inputPanelHeight, transition: .animated(duration: 0.25, curve: .spring), interfaceState: interfaceState)
                }
            default:
                break
        }
    }
    
    private func updatePaneDidScroll(pane: ChatMediaInputPane, state: ChatMediaInputPaneScrollState, transition: ContainedViewLayoutTransition) {
        var computedAbsoluteOffset: CGFloat
        if let absoluteOffset = state.absoluteOffset, absoluteOffset >= 0.0 {
            computedAbsoluteOffset = 0.0
        } else {
            computedAbsoluteOffset = pane.collectionListPanelOffset + state.relativeChange
        }
        computedAbsoluteOffset = max(-41.0, min(computedAbsoluteOffset, 0.0))
        pane.collectionListPanelOffset = computedAbsoluteOffset
        if transition.isAnimated {
            if pane.collectionListPanelOffset < -41.0 / 2.0 {
                pane.collectionListPanelOffset = -41.0
            } else {
                pane.collectionListPanelOffset = 0.0
            }
        }
        
        let collectionListPanelOffset = self.currentCollectionListPanelOffset()
        
        self.updateAppearanceTransition(transition: transition)
        transition.updateFrame(node: self.collectionListPanel, frame: CGRect(origin: CGPoint(x: 0.0, y: collectionListPanelOffset), size: self.collectionListPanel.bounds.size))
        transition.updateFrame(node: self.collectionListSeparator, frame: CGRect(origin: CGPoint(x: 0.0, y: 41.0 + collectionListPanelOffset), size: self.collectionListSeparator.bounds.size))
        transition.updatePosition(node: self.listView, position: CGPoint(x: self.listView.position.x, y: (41.0 - collectionListPanelOffset) / 2.0))
    }
    
    private func fixPaneScroll(pane: ChatMediaInputPane, state: ChatMediaInputPaneScrollState) {
        if let absoluteOffset = state.absoluteOffset, absoluteOffset >= 0.0 {
            pane.collectionListPanelOffset = 0.0
        } else {
            if pane.collectionListPanelOffset < -41.0 / 2.0 {
                pane.collectionListPanelOffset = -41.0
            } else {
                pane.collectionListPanelOffset = 0.0
            }
        }
        
        let collectionListPanelOffset = self.currentCollectionListPanelOffset()
        
        let transition = ContainedViewLayoutTransition.animated(duration: 0.25, curve: .spring)
        self.updateAppearanceTransition(transition: transition)
        transition.updateFrame(node: self.collectionListPanel, frame: CGRect(origin: CGPoint(x: 0.0, y: collectionListPanelOffset), size: self.collectionListPanel.bounds.size))
        transition.updateFrame(node: self.collectionListSeparator, frame: CGRect(origin: CGPoint(x: 0.0, y: 41.0 + collectionListPanelOffset), size: self.collectionListSeparator.bounds.size))
        transition.updatePosition(node: self.listView, position: CGPoint(x: self.listView.position.x, y: (41.0 - collectionListPanelOffset) / 2.0))
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let stickerSearchContainerNode = self.stickerSearchContainerNode {
            if let result = stickerSearchContainerNode.hitTest(point.offsetBy(dx: -stickerSearchContainerNode.frame.minX, dy: -stickerSearchContainerNode.frame.minY), with: event) {
                return result
            }
        }
        return super.hitTest(point, with: event)
    }
    
    static func setupPanelIconInsets(item: ListViewItem, previousItem: ListViewItem?, nextItem: ListViewItem?) -> UIEdgeInsets {
        var insets = UIEdgeInsets()
        if previousItem != nil {
            insets.top += 3.0
        }
        if nextItem != nil {
            insets.bottom += 3.0
        }
        return insets
    }
    
    private func dismissPeerSpecificPackSetup() {
        guard let peerId = self.peerId else {
            return
        }
        self.dismissedPeerSpecificStickerPack.set(.single(true))
        let _ = (self.account.postbox.transaction { transaction -> Void in
            transaction.updatePeerChatInterfaceState(peerId, update: { current in
                if let current = current as? ChatInterfaceState {
                    return current.withUpdatedMessageActionsState({ $0.withUpdatedClosedPeerSpecificPackSetup(true) })
                } else {
                    return current
                }
            })
        }).start()
    }
}
