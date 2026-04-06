// DynamicIslandWindow.swift
// A borderless NSPanel that sits at the top-center of the primary screen,
// always above other windows, shaped like a pill — the "Dynamic Island" for
// Claude Monitor.

import AppKit
import SwiftUI

final class DynamicIslandWindow: NSPanel {

    private let store: SessionStore
    private var hostingView: NSHostingView<DynamicIslandView>!

    // Sizes
    static let collapsedSize = CGSize(width: 260, height: 40)
    static let expandedWidth: CGFloat = 420

    init(store: SessionStore) {
        self.store = store
        super.init(
            contentRect: NSRect(origin: .zero, size: DynamicIslandWindow.collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Window properties
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false          // we draw our own shadow in SwiftUI
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.acceptsMouseMovedEvents = true

        // SwiftUI content
        let view = DynamicIslandView(store: store, window: self)
        hostingView = NSHostingView(rootView: view)
        hostingView.frame = self.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView

        positionAtTopCenter()
        startObservingScreenChanges()
    }

    // MARK: - Sizing

    func resize(to newSize: CGSize, animated: Bool) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let x = screenFrame.midX - newSize.width / 2
        // Pin to top: a bit below the very top edge (notch area)
        let topOffset: CGFloat = 8
        let y = screenFrame.maxY - newSize.height - topOffset

        let newFrame = NSRect(x: x, y: y, width: newSize.width, height: newSize.height)

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.38
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0) // spring-like
                self.animator().setFrame(newFrame, display: true)
            }
        } else {
            self.setFrame(newFrame, display: true)
        }
    }

    // MARK: - Positioning

    func positionAtTopCenter() {
        let size = self.frame.size.width > 0 ? self.frame.size : DynamicIslandWindow.collapsedSize
        resize(to: size, animated: false)
    }

    // MARK: - Hit testing: pass clicks through transparent/empty areas

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Screen changes

    private func startObservingScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenDidChange() {
        positionAtTopCenter()
    }
}
