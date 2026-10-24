import Cocoa

func makeEditMenuItem() -> NSMenuItem {
    let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    let menu = NSMenu(title: "Edit")
    // Nil targets let the focused field editor handle the standard shortcuts,
    // including the secure API-key field in the settings panel.
    menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    menu.addItem(.separator())
    menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    item.submenu = menu
    return item
}
