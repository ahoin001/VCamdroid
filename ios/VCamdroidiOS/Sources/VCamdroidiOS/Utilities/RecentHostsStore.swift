import Foundation

/// Persists recently used Windows host IPs for manual connection.
public enum RecentHostsStore {
    private static let key = "vcamdroid.recentHosts"
    private static let maxCount = 8

    public static func load() -> [String] {
        (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .filter { !$0.isEmpty }
    }

    public static func remember(_ host: String) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var hosts = load().filter { $0 != trimmed }
        hosts.insert(trimmed, at: 0)
        if hosts.count > maxCount {
            hosts = Array(hosts.prefix(maxCount))
        }
        UserDefaults.standard.set(hosts, forKey: key)
    }
}
