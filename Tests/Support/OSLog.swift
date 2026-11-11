// Linux-only no-op logging for deterministic OS doubles. Apple CI uses OSLog.
struct Logger {
    enum Privacy { case `public` }
    struct Message: ExpressibleByStringInterpolation {
        init(stringLiteral: String) {}
        init(stringInterpolation: StringInterpolation) {}
        struct StringInterpolation: StringInterpolationProtocol {
            init(literalCapacity: Int, interpolationCount: Int) {}
            mutating func appendLiteral(_ literal: String) {}
            mutating func appendInterpolation<T>(_ value: T) {}
            mutating func appendInterpolation<T>(_ value: T, privacy: Privacy) {}
        }
    }
    init(subsystem: String, category: String) {}
    func notice(_ message: Message) {}
    func error(_ message: Message) {}
}
