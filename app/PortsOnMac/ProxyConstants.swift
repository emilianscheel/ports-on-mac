import Foundation

enum ProxyConstants {
    static let userProxyPort: UInt16 = 19820
    static let httpPort: UInt16 = 80
    static let machServiceName = "com.emilianscheel.ports-on-mac.forwarder"
    static let launchDaemonPlistName = "com.emilianscheel.ports-on-mac.forwarder.plist"
    static let appBundleIdentifier = "com.emilianscheel.ports-on-mac"
    static let hostsBeginMarker = "# ports-on-mac begin"
    static let hostsEndMarker = "# ports-on-mac end"
    static let hostsPath = "/etc/hosts"
}
