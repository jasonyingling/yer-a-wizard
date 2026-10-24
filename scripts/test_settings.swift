import Cocoa
import Security

@main struct SettingsTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let edit = makeEditMenuItem().submenu!
        for (title, key, action) in [("Paste", "v", "paste:"), ("Select All", "a", "selectAll:"),
                                     ("Copy", "c", "copy:"), ("Cut", "x", "cut:")] {
            let item = edit.item(withTitle: title)!
            precondition(item.keyEquivalent == key && item.keyEquivalentModifierMask == .command)
            precondition(item.action == Selector(action) && item.target == nil)
        }

        var saved: String?
        var saves = 0
        var rejectWrite = false
        var rejectRead = false
        var truncateWrite = false
        let store = VoiceSettingsKeyStore(load: {
            if rejectRead { throw VoiceKeyStore.AccessError(status: errSecAuthFailed) }
            return saved
        }, save: { key in
            saves += 1
            if rejectWrite { return errSecAuthFailed }
            saved = truncateWrite ? String(key.prefix(20)) : key
            return errSecSuccess
        }, delete: { saved = nil; return errSecSuccess })
        let controller = WandVoiceController(settingsKeyStore: store)
        controller.showSettings()
        let window = NSApp.windows.first { $0.title == "Voice settings" }!
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let views = descendants(window.contentView!)
        func field(_ id: String) -> NSTextField {
            views.first { $0.identifier?.rawValue == id } as! NSTextField
        }
        func click(_ title: String) {
            (views.first { ($0 as? NSButton)?.title == title } as! NSButton).performClick(nil)
        }
        let input = field("voice-api-key")
        let keyStatus = field("voice-key-status")
        let entryStatus = field("voice-key-entry-status")
        let status = field("voice-settings-status")
        func enter(_ text: String) {
            input.stringValue = text
            controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: input))
        }
        precondition(keyStatus.stringValue.contains("No API key saved"))
        let dummy = "sk-test-" + String(repeating: "x", count: 180)
        enter("  \(dummy)\n")
        precondition(entryStatus.stringValue.contains("188 characters entered"))
        controller.showSettings()
        precondition(!input.stringValue.isEmpty, "Opening an already visible panel preserves unsaved input")
        click("Save settings")
        precondition(saved == dummy && saves == 1, "Long keys must be stored in full")
        precondition(status.stringValue.contains("verified in Keychain") && window.isVisible)
        precondition(input.stringValue.isEmpty && keyStatus.stringValue.contains("188 characters"))
        click("Done"); controller.showSettings()
        precondition(input.stringValue.isEmpty && keyStatus.stringValue.contains("API key saved"))
        click("Save settings")
        precondition(saves == 1 && saved == dummy, "Blank input preserves the saved key")

        rejectWrite = true; enter("replacement-test-key"); click("Save settings")
        precondition(status.stringValue.contains("Could not save") && !input.stringValue.isEmpty && saved == dummy)
        rejectWrite = false; rejectRead = true; click("Save settings")
        precondition(status.stringValue.contains("Could not read back") && !input.stringValue.isEmpty)
        rejectRead = false; truncateWrite = true; enter(dummy); click("Save settings")
        precondition(status.stringValue.contains("Could not verify") && !input.stringValue.isEmpty)
        truncateWrite = false; click("Save settings")
        precondition(saved == dummy && status.stringValue.contains("verified in Keychain"))
        click("Remove saved key")
        precondition(saved == nil && keyStatus.stringValue.contains("No API key saved"))
        rejectRead = true; click("Done"); controller.showSettings()
        precondition(keyStatus.stringValue.contains("Could not access Keychain"), "Access failure must not claim no saved key")
        click("Done"); controller.shutdown()
        print("PASS: standard editing shortcuts, long key persistence, input count, visible save confirmation, reopen status, blank preservation, write/read failures, readback mismatch and removal (isolated fake storage)")
    }
}
