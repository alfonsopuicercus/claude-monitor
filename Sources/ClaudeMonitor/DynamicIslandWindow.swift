// DynamicIslandWindow.swift
// A borderless NSPanel that hugs the very top of the chosen screen.

import AppKit
import SwiftUI

extension Notification.Name {
    static let pinnedScreenChanged = Notification.Name("ClaudeMonitorPinnedScreenChanged")
}

/// Ensures the first mouse-down activates buttons rather than just making the panel key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class DynamicIslandWindow: NSPanel {

    static let barHeight: CGFloat    = 42
    static let expandedWidth: CGFloat = 420
    static var collapsedSize: CGSize { CGSize(width: 310, height: barHeight) }

    private let store: SessionStore

    init(store: SessionStore) {
        self.store = store
        super.init(
            contentRect: NSRect(origin: .zero, size: DynamicIslandWindow.collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level           = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        backgroundColor = .clear
        isOpaque        = false
        hasShadow       = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true

        // Seed the pinned screen default to the primary display if not yet set
        if UserDefaults.standard.string(forKey: "claudeMonitor.pinnedScreen") == nil {
            UserDefaults.standard.set(
                NSScreen.screens.first?.localizedName ?? "",
                forKey: "claudeMonitor.pinnedScreen"
            )
        }

        let view = DynamicIslandView(store: store, window: self)
        let hv   = FirstMouseHostingView(rootView: view)
        hv.autoresizingMask = [.width, .height]
        contentView = hv

        snapToTop(size: DynamicIslandWindow.collapsedSize, animated: false)

        NotificationCenter.default.addObserver(
            self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenChanged),
            name: .pinnedScreenChanged, object: nil
        )
    }

    // MARK: - Public resize API

    func resize(to size: CGSize, animated: Bool) {
        snapToTop(size: size, animated: animated)
    }

    // MARK: - Private helpers

    /// The screen to pin to: the stored preference, falling back to the primary display.
    private var preferredScreen: NSScreen {
        let stored = UserDefaults.standard.string(forKey: "claudeMonitor.pinnedScreen") ?? ""
        return NSScreen.screens.first(where: { $0.localizedName == stored })
            ?? NSScreen.screens.first
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func snapToTop(size: CGSize, animated: Bool) {
        let sr = preferredScreen.frame
        let x = (sr.width - size.width) / 2 + sr.minX
        let y = sr.maxY - size.height
        let newFrame = NSRect(x: x, y: y, width: size.width, height: size.height)

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.36
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.5, 0.64, 1.0)
                animator().setFrame(newFrame, display: true)
            }
        } else {
            setFrame(newFrame, display: false)
        }
    }

    @objc private func screenChanged() {
        snapToTop(size: frame.size, animated: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
