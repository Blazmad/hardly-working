import Foundation

/// A UserDefaults that never touches disk, one fresh instance per test.
///
/// A real suite cannot be cleaned up: once a domain has been written, cfprefsd
/// rewrites its plist after removePersistentDomain, synchronize or deleting the
/// file, so every run left an empty plist per test in ~/Library/Preferences.
/// Keeping the values in memory is the only way to leave nothing behind.
final class InMemoryDefaults: UserDefaults {
    private var registered: [String: Any] = [:]
    private var values: [String: Any] = [:]

    init() {
        /// Never written to (every accessor Settings uses is overridden below),
        /// and named so that a missed override would land in a test domain,
        /// never in the app's real preferences: the test host is the app.
        super.init(suiteName: "com.madzar.hardlyworking.tests.in-memory")!
    }

    override func register(defaults: [String: Any]) {
        registered.merge(defaults) { _, new in new }
    }

    override func object(forKey key: String) -> Any? {
        values[key] ?? registered[key]
    }

    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func set(_ value: Bool, forKey key: String) { values[key] = value }
    override func set(_ value: Int, forKey key: String) { values[key] = value }

    override func removeObject(forKey key: String) { values[key] = nil }

    override func bool(forKey key: String) -> Bool {
        (object(forKey: key) as? NSNumber)?.boolValue ?? false
    }

    override func integer(forKey key: String) -> Int {
        (object(forKey: key) as? NSNumber)?.intValue ?? 0
    }
}
