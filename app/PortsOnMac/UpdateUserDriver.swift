import AppKit
import Sparkle

/// Sparkle user driver that skips confirmation dialogs and installs immediately,
/// while still showing checking/download progress and an up-to-date alert.
@MainActor
final class UpdateUserDriver: NSObject, SPUUserDriver {
    private let standard: SPUStandardUserDriver

    init(hostBundle: Bundle) {
        standard = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)
        super.init()
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        standard.showUserInitiatedUpdateCheck(cancellation: cancellation)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if appcastItem.isInformationOnlyUpdate {
            NSApp.activate(ignoringOtherApps: true)
            standard.showUpdateFound(with: appcastItem, state: state, reply: reply)
            return
        }
        reply(.install)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        standard.showUpdateReleaseNotes(with: downloadData)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        standard.showUpdateReleaseNotesFailedToDownloadWithError(error)
    }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "You’re up to date"
        if let version, !version.isEmpty {
            alert.informativeText = "Ports on Mac \(version) is the latest version."
        } else {
            alert.informativeText = "You already have the newest version of Ports on Mac."
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        standard.showUpdaterError(error, acknowledgement: acknowledgement)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        standard.showDownloadInitiated(cancellation: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        standard.showDownloadDidReceiveExpectedContentLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        standard.showDownloadDidReceiveData(ofLength: length)
    }

    func showDownloadDidStartExtractingUpdate() {
        standard.showDownloadDidStartExtractingUpdate()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        standard.showExtractionReceivedProgress(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        reply(.install)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        standard.showInstallingUpdate(
            withApplicationTerminated: applicationTerminated,
            retryTerminatingApplication: retryTerminatingApplication
        )
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
    }

    func dismissUpdateInstallation() {
        standard.dismissUpdateInstallation()
    }

    func showUpdateInFocus() {
        NSApp.activate(ignoringOtherApps: true)
        standard.showUpdateInFocus()
    }
}
