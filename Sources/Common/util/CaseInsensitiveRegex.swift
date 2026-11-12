import Foundation
import os

/// https://github.com/swiftlang/swift-experimental-string-processing/issues/792
/// https://forums.swift.org/t/should-regex-be-sendable/69529
public struct CaseInsensitiveRegex: Equatable, Sendable {
    public let origin: String
    fileprivate nonisolated(unsafe) let regex: Regex<AnyRegexOutput>

    private init(_ origin: String, _ regex: Regex<AnyRegexOutput>) {
        self.origin = origin
        unsafe self.regex = regex
    }

    public static func new(_ str: String) -> ResOrStr<CaseInsensitiveRegex> {
        Result { try Regex(str) }
            .mapError { e in "Can't parse \(str.singleQuoted) regex: \(e.localizedDescription)" }
            .map { CaseInsensitiveRegex(str, $0.ignoresCase()) }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.origin == rhs.origin }
}

extension String {
    @MainActor public func contains(caseInsensitiveRegex regex: CaseInsensitiveRegex) -> Bool {
        self.contains(unsafe regex.regex)
    }

    /// The regex engine backtracks and can't be interrupted. A pathological pattern (e.g. '(a+)+$') may run for years
    /// on an input that is only a few dozen characters long. That's why the regex runs on a separate thread and the
    /// caller gives up after the timeout. The thread itself can't be stopped, it keeps running in the background.
    ///
    /// - Returns: nil if the regex didn't finish in time
    public func contains(caseInsensitiveRegex regex: CaseInsensitiveRegex, timeoutMs: Int) async -> Bool? {
        let string = self
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool?, Never>) in
            let pending = OSAllocatedUnfairLock<CheckedContinuation<Bool?, Never>?>(initialState: continuation)
            let resumeOnce: @Sendable (Bool?) -> () = { value in
                let continuation = pending.withLock { state in
                    let result = state
                    state = nil
                    return result
                }
                continuation?.resume(returning: value)
            }
            let thread = Thread { resumeOnce(string.contains(unsafe regex.regex)) }
            thread.name = "hyprspace-regex"
            thread.start()
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) { resumeOnce(nil) }
        }
    }
}
