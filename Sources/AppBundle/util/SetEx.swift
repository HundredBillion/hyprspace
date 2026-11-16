import OrderedCollections

// periphery:ignore
extension Set {
    func toArray() -> [Element] { Array(self) }

    @inlinable static func += (lhs: inout Set<Element>, rhs: any Sequence<Element>) {
        lhs.formUnion(rhs)
    }

    @inlinable static func -= (lhs: inout Set<Element>, rhs: any Sequence<Element>) {
        lhs.subtract(rhs)
    }
}

extension Sequence where Element: Hashable {
    func toOrderedSet() -> OrderedSet<Element> { OrderedSet(self) }
}
