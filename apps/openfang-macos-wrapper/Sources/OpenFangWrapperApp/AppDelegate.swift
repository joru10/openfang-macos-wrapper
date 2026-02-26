import AppKit

@MainActor
final class AppBridge {
    static weak var state: AppState?
}

@MainActor
final class WrapperAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state = AppBridge.state,
              state.controller.status == .running || state.controller.status == .runningExternal else {
            return .terminateNow
        }

        switch state.settings.quitBehavior {
        case .stopAndQuit:
            Task { @MainActor in
                let success = await state.stopOpenFangAndWait()
                NSApp.reply(toApplicationShouldTerminate: success)
            }
            return .terminateLater
        case .leaveRunning:
            return .terminateNow
        case .ask:
            let alert = NSAlert()
            alert.messageText = "OpenFang is running"
            alert.informativeText = "Choose whether to stop OpenFang before quitting."
            alert.addButton(withTitle: "Stop and Quit")
            alert.addButton(withTitle: "Leave Running and Quit")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                Task { @MainActor in
                    let success = await state.stopOpenFangAndWait()
                    NSApp.reply(toApplicationShouldTerminate: success)
                }
                return .terminateLater
            }
            if response == .alertSecondButtonReturn {
                return .terminateNow
            }
            return .terminateCancel
        }
    }
}
