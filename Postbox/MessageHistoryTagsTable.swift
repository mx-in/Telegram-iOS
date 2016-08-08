import Foundation

class MessageHistoryTagsTable: Table {
    private let sharedKey = ValueBoxKey(length: 8 + 4 + 4 + 4 + 4)
    
    override init(valueBox: ValueBox, tableId: Int32) {
        super.init(valueBox: valueBox, tableId: tableId)
    }
    
    private func key(_ tagMask: MessageTags, index: MessageIndex, key: ValueBoxKey = ValueBoxKey(length: 8 + 4 + 4 + 4 + 4)) -> ValueBoxKey {
        key.setInt64(0, value: index.id.peerId.toInt64())
        key.setUInt32(8, value: tagMask.rawValue)
        key.setInt32(8 + 4, value: index.timestamp)
        key.setInt32(8 + 4 + 4, value: index.id.namespace)
        key.setInt32(8 + 4 + 4 + 4, value: index.id.id)
        return key
    }
    
    private func lowerBound(_ tagMask: MessageTags, peerId: PeerId) -> ValueBoxKey {
        let key = ValueBoxKey(length: 8 + 4)
        key.setInt64(0, value: peerId.toInt64())
        key.setUInt32(8, value: tagMask.rawValue)
        return key
    }
    
    private func upperBound(_ tagMask: MessageTags, peerId: PeerId) -> ValueBoxKey {
        let key = ValueBoxKey(length: 8 + 4)
        key.setInt64(0, value: peerId.toInt64())
        key.setUInt32(8, value: tagMask.rawValue)
        return key.successor
    }
    
    func add(_ tagMask: MessageTags, index: MessageIndex) {
        self.valueBox.set(self.tableId, key: self.key(tagMask, index: index, key: self.sharedKey), value: MemoryBuffer())
    }
    
    func remove(_ tagMask: MessageTags, index: MessageIndex) {
        self.valueBox.remove(self.tableId, key: self.key(tagMask, index: index, key: self.sharedKey))
    }
    
    func entryLocation(at index: MessageIndex, tagMask: MessageTags) -> MessageHistoryEntryLocation? {
        if let _ = self.valueBox.get(self.tableId, key: self.key(tagMask, index: index)) {
            var greaterCount = 0
            self.valueBox.range(self.tableId, start: self.key(tagMask, index: index), end: self.upperBound(tagMask, peerId: index.id.peerId), keys: { _ in
                greaterCount += 1
                return true
            }, limit: 0)
            
            var lowerCount = 0
            self.valueBox.range(self.tableId, start: self.key(tagMask, index: index), end: self.lowerBound(tagMask, peerId: index.id.peerId), keys: { _ in
                lowerCount += 1
                return true
            }, limit: 0)
            
            return MessageHistoryEntryLocation(index: lowerCount, count: greaterCount + lowerCount + 1)
        }
        return nil
    }
    
    func indicesAround(_ tagMask: MessageTags, index: MessageIndex, count: Int) -> (indices: [MessageIndex], lower: MessageIndex?, upper: MessageIndex?) {
        var lowerEntries: [MessageIndex] = []
        var upperEntries: [MessageIndex] = []
        var lower: MessageIndex?
        var upper: MessageIndex?
        
        self.valueBox.range(self.tableId, start: self.key(tagMask, index: index), end: self.lowerBound(tagMask, peerId: index.id.peerId), keys: { key in
            let index = MessageIndex(id: MessageId(peerId: PeerId(key.getInt64(0)), namespace: key.getInt32(8 + 4 + 4), id: key.getInt32(8 + 4 + 4 + 4)), timestamp: key.getInt32(8 + 4))
            lowerEntries.append(index)
            return true
        }, limit: count / 2 + 1)
        
        if lowerEntries.count >= count / 2 + 1 {
            lower = lowerEntries.last
            lowerEntries.removeLast()
        }
        
        self.valueBox.range(self.tableId, start: self.key(tagMask, index: index).predecessor, end: self.upperBound(tagMask, peerId: index.id.peerId), keys: { key in
            let index = MessageIndex(id: MessageId(peerId: PeerId(key.getInt64(0)), namespace: key.getInt32(8 + 4 + 4), id: key.getInt32(8 + 4 + 4 + 4)), timestamp: key.getInt32(8 + 4))
            upperEntries.append(index)
            return true
        }, limit: count - lowerEntries.count + 1)
        if upperEntries.count >= count - lowerEntries.count + 1 {
            upper = upperEntries.last
            upperEntries.removeLast()
        }
        
        if lowerEntries.count != 0 && lowerEntries.count + upperEntries.count < count {
            var additionalLowerEntries: [MessageIndex] = []
            self.valueBox.range(self.tableId, start: self.key(tagMask, index: lowerEntries.last!), end: self.lowerBound(tagMask, peerId: index.id.peerId), keys: { key in
                let index = MessageIndex(id: MessageId(peerId: PeerId(key.getInt64(0)), namespace: key.getInt32(8 + 4 + 4), id: key.getInt32(8 + 4 + 4 + 4)), timestamp: key.getInt32(8 + 4))
                additionalLowerEntries.append(index)
                return true
            }, limit: count - lowerEntries.count - upperEntries.count + 1)
            if additionalLowerEntries.count >= count - lowerEntries.count + upperEntries.count + 1 {
                lower = additionalLowerEntries.last
                additionalLowerEntries.removeLast()
            }
            lowerEntries.append(contentsOf: additionalLowerEntries)
        }
        
        var entries: [MessageIndex] = []
        entries.append(contentsOf: lowerEntries.reversed())
        entries.append(contentsOf: upperEntries)
        return (indices: entries, lower: lower, upper: upper)
    }
    
    func earlierIndices(_ tagMask: MessageTags, peerId: PeerId, index: MessageIndex?, count: Int) -> [MessageIndex] {
        var indices: [MessageIndex] = []
        let key: ValueBoxKey
        if let index = index {
            key = self.key(tagMask, index: index)
        } else {
            key = self.upperBound(tagMask, peerId: peerId)
        }
        self.valueBox.range(self.tableId, start: key, end: self.lowerBound(tagMask, peerId: peerId), keys: { key in
            let index = MessageIndex(id: MessageId(peerId: PeerId(key.getInt64(0)), namespace: key.getInt32(8 + 4 + 4), id: key.getInt32(8 + 4 + 4 + 4)), timestamp: key.getInt32(8 + 4))
            indices.append(index)
            return true
        }, limit: count)
        return indices
    }
    
    func laterIndices(_ tagMask: MessageTags, peerId: PeerId, index: MessageIndex?, count: Int) -> [MessageIndex] {
        var indices: [MessageIndex] = []
        let key: ValueBoxKey
        if let index = index {
            key = self.key(tagMask, index: index)
        } else {
            key = self.lowerBound(tagMask, peerId: peerId)
        }
        self.valueBox.range(self.tableId, start: key, end: self.upperBound(tagMask, peerId: peerId), keys: { key in
            let index = MessageIndex(id: MessageId(peerId: PeerId(key.getInt64(0)), namespace: key.getInt32(8 + 4 + 4), id: key.getInt32(8 + 4 + 4 + 4)), timestamp: key.getInt32(8 + 4))
            indices.append(index)
            return true
        }, limit: count)
        return indices
    }
}
