import Foundation

@objc protocol ProxyHelperXPCProtocol {
    func setLiveDomains(_ domains: [String], withReply reply: @escaping (Bool, String?) -> Void)
}
