// DynamicIslandWindow.swift
// A borderless NSPanel that hugs the very top of the primary screen — exactly
// like the iPhone Dynamic Island: square top corners, rounded bottom corners,
// always above other windows.

import AppKit
import SwiftUI

final class DynamicIslandWindow: NSPanel {

    static let barHeight: CGFloat   = 42     // collapsed bar height
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
        hasShadow       = false   // shadow drawn by SwiftUI
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true

        let view = DynamicIslandView(store: store, window: self)
        let hv   = NSHostingView(rootView: view)
        hv.autoresizingMask = [.width, .height]
        contentView = hv

        snapToTop(size: DynamicIslandWindow.collapsedSize, animated: false)

        NotificationCenter.default.addObserver(
            self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    // MARK: - Public resize API

    func resize(to size: CGSize, animated: Bool) {
        snapToTop(size: size, animated: animated)
    }

    // MARK: - Private helpers

    private func snapToTop(size: CGSize, animated: Bool) {
        guard let screen = NSScreen.main else { return }
        let sr = screen.frame
        // Pin to the very top center — y puts the TOP of the window at screen.maxY
        let x = (sr.width - size.width) / 2 + sr.minX
        let y = sr.maxY - size.height       // flush to top
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
