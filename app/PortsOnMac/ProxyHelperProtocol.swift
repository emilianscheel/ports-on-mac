import Foundation

@objc protocol ProxyHelperHTTPXPCProtocol {
    func setLiveDomains(_ domains: [String], withReply reply: @escaping (Bool, String?) -> Void)
}

@objc protocol ProxyHelperXPCProtocol {
    func setLiveDomains(_ domains: [String], withReply reply: @escaping (Bool, String?) -> Void)
    func setLiveDomains(_ domains: [String], enableHTTPS: Bool, withReply reply: @escaping (Bool, String?) -> Void)
    func installTrustedRoot(_ certificateDER: Data, withReply reply: @escaping (Bool, String?) -> Void)
}
