import Darwin
import Foundation

enum ProcessMetadata {
    static func executablePath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return nil }
        return String(cString: buffer)
    }

    static func currentWorkingDirectory(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard ports_on_mac_pid_cwd(pid, &buffer, Int32(buffer.count)) == 0 else {
            return nil
        }
        let path = String(cString: buffer)
        return path.isEmpty ? nil : path
    }

    static func bundleURL(containingExecutable path: String) -> URL? {
        var url = URL(fileURLWithPath: path)
        while url.path != "/" {
            if url.pathExtension == "app" {
                return url
            }
            url.deleteLastPathComponent()
        }
        return nil
    }

    static func bundleIdentifier(executablePath: String?) -> String? {
        guard let executablePath, let bundleURL = bundleURL(containingExecutable: executablePath) else {
            return nil
        }

        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: infoURL) else {
            return nil
        }

        return plist["CFBundleIdentifier"] as? String
    }
}
