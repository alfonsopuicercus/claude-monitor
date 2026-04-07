// AppDelegate.swift
// Sets up the Dynamic Island overlay window and (optionally) a minimal menu bar icon.

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    var islandWindow: DynamicIslandWindow!
    var store: SessionStore!

    // Minimal menu bar item as a fallback / quit handle
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ignore SIGPIPE so writing to a closed socket returns EPIPE instead of crashing
        signal(SIGPIPE, SIG_IGN)

        NSApp.setActivationPolicy(.accessory)

        store = SessionStore()

        // Dynamic Island overlay
        islandWindow = DynamicIslandWindow(store: store)
        islandWindow.makeKeyAndOrderFront(nil)
        // Re-snap after the run loop settles so the window lands on the pinned screen,
        // not whichever screen AppKit chose at init time.
        DispatchQueue.main.async { self.islandWindow.snapToPreferredScreen() }

        // Tiny menu bar icon (just for quitting gracefully)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "terminal.fill",
                                accessibilityDescription: "Claude Monitor")
            btn.image?.isTemplate = true
            let menu = NSMenu()
            menu.addItem(withTitle: "Claude Monitor", action: nil, keyEquivalent: "")
                .isEnabled = false
            menu.addItem(.separator())
            menu.addItem(withTitle: "Toggle Island", action: #selector(toggleIsland), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
        }
    }

    @objc private func toggleIsland() {
        if islandWindow.isVisible {
            islandWindow.orderOut(nil)
        } else {
            islandWindow.makeKeyAndOrderFront(nil)
        }
    }
}
