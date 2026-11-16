import Foundation
import AppKit

public protocol HyprAny {}

extension HyprAny {
    @discardableResult
    @inlinable
    public func apply(_ block: (Self) -> Void) -> Self {
        block(self)
        return self
    }

    @discardableResult
    @inlinable
    public func also(_ block: (Self) -> Void) -> Self {
        block(self)
        return self
    }

    @inlinable public func takeIf(_ predicate: (Self) -> Bool) -> Self? { predicate(self) ? self : nil }
    @inlinable public func then<R>(_ body: (Self) -> R) -> R { body(self) }

    var noopKeyPath: () {
        get { () }
        set {} // swiftlint:disable:this unused_setter_value
    }
}

extension Int: HyprAny {}
extension String: HyprAny {}
extension Character: HyprAny {}
extension Regex: HyprAny {}
extension Array: HyprAny {}
extension URL: HyprAny {}
extension CGFloat: HyprAny {}
extension AXUIElement: HyprAny {}
extension CGPoint: HyprAny {}
