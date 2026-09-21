import Foundation

/// Holds a weak reference so a test can assert that an object deallocated.
///
/// This exists because `AGENTS.md` requires weak reference bindings to be
/// `var` (see docs/swift-ci-compatibility.md, run 34753843803), while the
/// compiler warns about a `weak var` local that is only ever read. A weak `var`
/// stored property satisfies both: the rule keeps its exact spelling, and the
/// diagnostic goes away without weakening any test.
final class DeinitProbeRef<T: AnyObject> {
    weak var value: T?

    init(_ object: T?) {
        value = object
    }
}

enum DeinitProbe {
    /// - Parameter object: the strong reference to observe. Pass the variable
    ///   itself, then set that variable to nil and read `probe.value`.
    @discardableResult
    static func track<T: AnyObject>(_ object: T?) -> DeinitProbeRef<T> {
        DeinitProbeRef(object)
    }
}
