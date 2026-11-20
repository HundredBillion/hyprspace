import Common
import Foundation

actor AwaitableOneTimeBroadcastLatch {
    private var done = false
    private var awaiters: [UniqueToken: AwaiterBox] = [:]

    func await(_ cm: CancellationMode) async throws {
        try checkCancellation(cm)
        if done { return }

        let id = UniqueToken()
        try await withTaskCancellationHandler {
            try await withStrictContinuation(of: Void.self, throwing: (any Error).self) { cont in
                switch takeAwaiter(id) {
                    case .cancelled: cont.resume(throwing: CancellationError())
                    case .waiting: die()
                    case nil where done: cont.resume()
                    case nil: check(awaiters.updateValue(AwaiterBox(.waiting(cont)), forKey: id) == nil)
                }
            }
        } onCancel: {
            if cm == .cancellable {
                Task.startUnstructured { await self.cancel(id: id) }
            }
        }
    }

    private func cancel(id: UniqueToken) {
        switch takeAwaiter(id) {
            case .waiting(let cont): cont.resume(throwing: CancellationError())
            case .cancelled: die()
            case nil where !done:
                // Indicate to 'await' that the client should be cancelled right away when it suspends
                awaiters[id] = AwaiterBox(.cancelled)
            case nil: break
        }
    }

    func signalToAll() {
        done = true
        for id in Array(awaiters.keys) {
            switch takeAwaiter(id) {
                case .waiting(let cont): cont.resume()
                case .cancelled: break
                case nil: break
            }
        }
    }

    private func takeAwaiter(_ id: UniqueToken) -> Awaiter? {
        awaiters.removeValue(forKey: id)?.take()
    }
}

private enum Awaiter: ~Copyable {
    case waiting(StrictContinuation<(), any Error>)
    case cancelled
}

/// A standard Dictionary can't hold noncopyable values. The box makes it possible without depending on
/// swift-collections' BasicContainers, which costs ~70 KB of machine code for this one use
private final class AwaiterBox {
    private var value: Awaiter?

    init(_ value: consuming Awaiter) { self.value = .some(value) }

    func take() -> Awaiter? { value.take() }
}
