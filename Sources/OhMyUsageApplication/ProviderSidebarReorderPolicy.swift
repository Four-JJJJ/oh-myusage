import Foundation

package enum ProviderSidebarReorderPolicy {
    package static func preview(ids: [String], draggingID: String, targetID: String, insertAfter: Bool) -> [String] {
        guard draggingID != targetID,
              let source = ids.firstIndex(of: draggingID),
              let target = ids.firstIndex(of: targetID) else { return ids }
        let destination = target + (insertAfter ? 1 : 0)
        guard source != destination, source + 1 != destination else { return ids }
        var result = ids
        result.remove(at: source)
        result.insert(draggingID, at: source < destination ? destination - 1 : destination)
        return result
    }
}
