// DynamicIslandView.swift
// Notch-style overlay. Hover to expand, click to toggle.
// Features: 8-bit animated character, live tool output, custom approval text.

import SwiftUI
import AppKit

// MARK: - Root view

struct DynamicIslandView: View {
    @ObservedObject var store: SessionStore
    weak var window: DynamicIslandWindow?

    @State private var expanded   = false
    @State private var hovering   = false
    @State private var collapseTimer: Timer?
    @State private var showSettings = false

    // Glow
    @State private var glowOpacity: Double = 0
    @State private var glowScale: CGFloat = 1.0

    var hasPermission: Bool { store.totalPermissionsWaiting > 0 }
    var isWorking: Bool    { store.sessions.contains { $0.status == .working } }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            VStack(spacing: 0) {
                collapsedBar
                    .frame(height: DynamicIslandWindow.barHeight)

                if expanded {
                    Divider().background(Color.white.opacity(0.08))

                    if showSettings {
                        SettingsPanel(store: store, onDone: { showSettings = false })
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        expandedPanel
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal:   .opacity.combined(with: .move(edge: .top))
                            ))
                    }
                }
            }
            .background(
                ZStack {
                    NotchShape()
                        .fill(glowColor.opacity(0.38))
                        .blur(radius: 22)
                        .scaleEffect(glowScale)
                        .opacity(glowOpacity)

                    NotchShape().fill(Color(white: 0.07))

                    NotchShape()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.13), Color.clear],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                }
                .shadow(color: .black.opacity(0.55), radius: 18, y: 7)
            )
            .clipShape(NotchShape())
            .contentShape(NotchShape())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // ── Hover: expand; leave: schedule collapse ──
        .onHover { isHovering in
            hovering = isHovering
            collapseTimer?.invalidate()
            collapseTimer = nil
            if isHovering {
                if !expanded {
                    withAnimation(.spring(response: 0.40, dampingFraction: 0.72)) { expanded = true }
                    updateWindowSize(expanded: true)
                }
            } else if !hasPermission {
                // Collapse 1.5 s after mouse leaves (unless permission pending)
                collapseTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                    withAnimation(.spring(response: 0.40, dampingFraction: 0.82)) { expanded = false }
                    updateWindowSize(expanded: false)
                }
            }
        }
        .onAppear { updateGlow() }
        .onChange(of: hasPermission) { pending in
            collapseTimer?.invalidate()
            collapseTimer = nil
            if pending && !expanded {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) { expanded = true }
                updateWindowSize(expanded: true)
            }
            withAnimation(.easeInOut(duration: 0.35)) {
                glowOpacity = pending ? 1.0 : (isWorking ? 0.45 : 0)
            }
            if pending { pulseGlow() }
        }
        .onChange(of: store.sessions.count) { _ in
            if expanded { updateWindowSize(expanded: true) }
            withAnimation { updateGlow() }
        }
        .onChange(of: store.sessions.map { $0.status.rawValue }.joined()) { _ in
            if expanded { updateWindowSize(expanded: true) }
            withAnimation { updateGlow() }
        }
    }

    // MARK: - Collapsed bar

    private var collapsedBar: some View {
        HStack(spacing: 10) {
            PixelCharacter(state: characterState)
                .frame(width: 32, height: 24)

            Group {
                if hasPermission {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text(permissionLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                } else if isWorking {
                    HStack(spacing: 6) {
                        Text("Working")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                        if let tool = activeTool { MiniToolBadge(name: tool) }
                    }
                } else if !store.sessions.isEmpty {
                    Text("\(store.sessions.count) session\(store.sessions.count == 1 ? "" : "s") idle")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.38))
                } else {
                    Text("Claude Monitor")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.28))
                }
            }
            .lineLimit(1)

            Spacer(minLength: 0)

            if store.sessions.count > 0 {
                Text("\(store.sessions.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
            }
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.22))
        }
        .padding(.horizontal, 14)
        // Click to toggle collapse (hover handles expand)
        .onTapGesture {
            collapseTimer?.invalidate()
            collapseTimer = nil
            withAnimation(.spring(response: 0.40, dampingFraction: 0.74)) { expanded.toggle() }
            updateWindowSize(expanded: expanded)
        }
    }

    // MARK: - Expanded panel

    private var expandedPanel: some View {
        VStack(spacing: 0) {
            if store.sessions.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(sortedSessions) { session in
                            SessionCard(session: session, store: store)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                }
                .frame(maxHeight: 400)
            }

            Divider().background(Color.white.opacity(0.06))

            HStack {
                Button(action: { withAnimation { showSettings.toggle() } }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.28))
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.22))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            PixelCharacter(state: .idle)
                .frame(width: 56, height: 44)
                .scaleEffect(2.0)
                .frame(width: 112, height: 88)
            Text("No sessions running")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.28))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Helpers

    private var sortedSessions: [ClaudeSession] {
        store.sessions.sorted {
            if $0.status == .waitingForPermission && $1.status != .waitingForPermission { return true }
            if $0.status != .waitingForPermission && $1.status == .waitingForPermission { return false }
            return $0.lastActivityAt > $1.lastActivityAt
        }
    }

    private var activeTool: String? { store.sessions.first { $0.currentTool != nil }?.currentTool }

    private var permissionLabel: String {
        let n = store.totalPermissionsWaiting
        if n == 1,
           let s = store.sessions.first(where: { $0.status == .waitingForPermission }),
           let p = s.pendingPermission { return "\(p.toolName) needs approval" }
        return "\(n) approvals needed"
    }

    private var glowColor: Color { hasPermission ? .orange : .green }

    private var characterState: PixelCharacterState {
        if hasPermission { return .alert }
        if isWorking     { return .working }
        return .idle
    }

    private func updateGlow() {
        glowOpacity = hasPermission ? 1.0 : (isWorking ? 0.45 : 0)
    }

    private func pulseGlow() {
        withAnimation(.easeInOut(duration: 0.4).repeatCount(3, autoreverses: true)) { glowScale = 1.12 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut(duration: 0.25)) { glowScale = 1.0 }
        }
    }

    private func updateWindowSize(expanded: Bool) {
        guard let window else { return }
        if !expanded { window.resize(to: DynamicIslandWindow.collapsedSize, animated: true); return }
        let base: CGFloat = DynamicIslandWindow.barHeight + 44
        let content: CGFloat = store.sessions.isEmpty ? 110 : CGFloat(store.sessions.count) * 118 + (hasPermission ? 80 : 0)
        let h = min(base + content, 560)
        window.resize(to: CGSize(width: DynamicIslandWindow.expandedWidth, height: h), animated: true)
    }
}

// MARK: - 8-bit pixel character

enum PixelCharacterState { case idle, working, alert }

struct PixelCharacter: View {
    var state: PixelCharacterState

    // Animation
    @State private var frame: Int = 0
    @State private var blink = false
    @State private var workSpin: Double = 0

    private let timer = Timer.publish(every: 0.22, on: .main, in: .common).autoconnect()
    private let blinkTimer = Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()

    // 8×10 pixel grid per frame. Colors: 0=clear 1=body 2=hi 3=eye 4=mouth 5=accent
    private let frames: [[UInt8]] = [
        // Frame 0 — neutral stand
        [0,0,1,1,1,1,0,0,
         0,1,1,1,1,1,1,0,
         0,1,3,1,1,3,1,0,
         0,1,1,1,1,1,1,0,
         0,0,1,2,2,1,0,0,
         2,1,1,1,1,1,1,2,
         0,0,1,1,1,1,0,0,
         0,0,1,1,1,1,0,0,
         0,0,1,0,0,1,0,0,
         0,0,1,0,0,1,0,0],
        // Frame 1 — slight bob / step A
        [0,0,1,1,1,1,0,0,
         0,1,1,1,1,1,1,0,
         0,1,3,1,1,3,1,0,
         0,1,1,1,1,1,1,0,
         0,0,1,2,2,1,0,0,
         2,1,1,1,1,1,1,2,
         0,0,1,1,1,1,0,0,
         0,0,1,1,1,1,0,0,
         0,0,0,1,1,0,0,0,
         0,0,1,0,0,1,0,0],
        // Frame 2 — step B
        [0,0,1,1,1,1,0,0,
         0,1,1,1,1,1,1,0,
         0,1,3,1,1,3,1,0,
         0,1,1,1,1,1,1,0,
         0,0,1,2,2,1,0,0,
         2,1,1,1,1,1,1,2,
         0,0,1,1,1,1,0,0,
         0,0,1,1,1,1,0,0,
         0,0,1,0,0,1,0,0,
         0,0,0,1,1,0,0,0],
        // Frame 3 — arms up / excited
        [0,0,1,1,1,1,0,0,
         0,1,1,1,1,1,1,0,
         0,1,3,1,1,3,1,0,
         0,1,1,5,5,1,1,0,
         0,0,1,2,2,1,0,0,
         0,1,1,1,1,1,1,0,
         2,0,1,1,1,1,0,2,
         0,0,1,1,1,1,0,0,
         0,0,1,0,0,1,0,0,
         0,0,1,0,0,1,0,0],
    ]

    private func color(for px: UInt8, state: PixelCharacterState, blink: Bool) -> Color {
        switch px {
        case 0: return .clear
        case 1: return Color(white: 0.25)
        case 2: return Color(white: 0.50)
        case 3: // eye
            if blink { return Color(white: 0.25) }
            switch state {
            case .idle:    return Color(red: 0.7, green: 0.95, blue: 1.0)
            case .working: return Color(red: 0.3, green: 1.0,  blue: 0.4)
            case .alert:   return Color(red: 1.0, green: 0.55, blue: 0.1)
            }
        case 4: return Color(white: 0.65)
        case 5: // accent
            switch state {
            case .idle:    return Color(red: 0.4, green: 0.8, blue: 1.0)
            case .working: return Color(red: 0.3, green: 1.0, blue: 0.4)
            case .alert:   return Color(red: 1.0, green: 0.5, blue: 0.1)
            }
        default: return .clear
        }
    }

    var body: some View {
        let cols = 8, rows = 10
        let px: CGFloat = 3   // pixel size

        let currentFrame = frames[frame % frames.count]

        Canvas { ctx, _ in
            for row in 0..<rows {
                for col in 0..<cols {
                    let idx = row * cols + col
                    guard idx < currentFrame.count else { continue }
                    let c = color(for: currentFrame[idx], state: state, blink: blink)
                    guard c != .clear else { continue }
                    let rect = CGRect(x: CGFloat(col) * px, y: CGFloat(row) * px, width: px, height: px)
                    ctx.fill(Path(rect), with: .color(c))
                }
            }
        }
        .frame(width: CGFloat(cols) * px, height: CGFloat(rows) * px)
        // Step through animation frames
        .onReceive(timer) { _ in
            let maxFrame: Int
            switch state {
            case .idle:    maxFrame = 2   // frames 0,1 only (gentle bob)
            case .working: maxFrame = 3   // frames 0-2 (walking)
            case .alert:   maxFrame = 3   // frames 0,3 (excited)
            }
            if state == .alert {
                frame = (frame == 0) ? 3 : 0   // toggle excited
            } else {
                frame = (frame + 1) % maxFrame
            }
        }
        .onReceive(blinkTimer) { _ in
            withAnimation(.easeInOut(duration: 0.06)) { blink = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeInOut(duration: 0.06)) { blink = false }
            }
        }
    }
}

// MARK: - Session card

struct SessionCard: View {
    let session: ClaudeSession
    @ObservedObject var store: SessionStore
    @State private var showInput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                StatusDot(color: Color(session.statusColor), pulsing: session.status == .working)
                    .frame(width: 14, height: 14)

                Text(session.displayCwd)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let tool = session.currentTool { MiniToolBadge(name: tool) }
                Spacer()
                Text(timeAgo(session.lastActivityAt))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.22))
            }
            .padding(.bottom, 5)

            // Last user prompt
            if let msg = session.lastUserMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.42))
                    .lineLimit(2)
                    .padding(.bottom, 4)
            }

            // Live tool input (collapsible)
            if session.currentTool != nil, let input = session.lastToolInput {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) { showInput.toggle() }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: showInput ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.28))
                        Text(inlinePreview(input))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                            .lineLimit(1)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                if showInput {
                    Text(input)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                        .textSelection(.enabled)
                        .lineLimit(8)
                        .padding(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(7)
                        .padding(.top, 3)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // Permission block
            if session.status == .waitingForPermission, let perm = session.pendingPermission {
                PermissionBlock(session: session, perm: perm, store: store)
                    .padding(.top, 7)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(session.status == .waitingForPermission
                    ? Color.orange.opacity(0.09)
                    : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            session.status == .waitingForPermission
                                ? Color.orange.opacity(0.28)
                                : Color.white.opacity(0.06),
                            lineWidth: 0.5
                        )
                )
        )
    }

    private func inlinePreview(_ raw: String) -> String {
        if let d = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            let val = (obj["command"] ?? obj["file_path"] ?? obj["query"] ?? obj.values.first) as? String ?? raw
            return val.components(separatedBy: .newlines).first.map { "▶ " + $0 } ?? raw
        }
        return "▶ " + (raw.components(separatedBy: .newlines).first ?? raw)
    }
}

// MARK: - Permission block (three options)

struct PermissionBlock: View {
    let session: ClaudeSession
    let perm: PermissionRequest
    @ObservedObject var store: SessionStore

    @State private var showCustom = false
    @State private var customText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Tool + input
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 10)).foregroundColor(.orange)
                Text("Permission — \(perm.toolName)")
                    .font(.system(size: 10, weight: .semibold)).foregroundColor(.orange)
            }

            if perm.toolInput != "{}" {
                Text(perm.toolInput)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.52))
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(7)
            }

            // Custom instruction field (appears when Edit tapped)
            if showCustom {
                HStack(spacing: 6) {
                    TextField("Add instruction for Claude…", text: $customText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.white.opacity(0.07))
                        .cornerRadius(7)
                        .onSubmit {
                            store.approveWithInstruction(sessionId: session.id, instruction: customText)
                        }
                    Button(action: {
                        store.approveWithInstruction(sessionId: session.id, instruction: customText)
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Buttons row: Deny | Edit & Approve | Approve
            HStack(spacing: 5) {
                // Deny
                Button(action: { store.denyPermission(sessionId: session.id) }) {
                    Label("Deny", systemImage: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.12))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                // Edit & Approve — shows text field
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) { showCustom.toggle() }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                        Text("Edit…")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(showCustom ? .yellow : .white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(showCustom ? 0.1 : 0.06))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                // Approve
                Button(action: { store.approvePermission(sessionId: session.id) }) {
                    Label("Approve", systemImage: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.12))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Notch shape

struct NotchShape: Shape {
    var cornerRadius: CGFloat = 22
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Pulsing status dot

struct StatusDot: View {
    let color: Color
    let pulsing: Bool
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.22)).scaleEffect(scale)
            Circle().fill(color).frame(width: 6, height: 6)
        }
        .onAppear {
            guard pulsing else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { scale = 1.7 }
        }
    }
}

// MARK: - Settings panel

struct SettingsPanel: View {
    @ObservedObject var store: SessionStore
    var onDone: () -> Void

    @AppStorage("claudeMonitor.autoExpand")    var autoExpand   = true
    @AppStorage("claudeMonitor.idleTimeout")   var idleTimeout  = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                Spacer()
                Button(action: onDone) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14)).foregroundColor(.white.opacity(0.28))
                }.buttonStyle(.plain)
            }

            Divider().background(Color.white.opacity(0.1))

            SettingRow(label: "Auto-expand on permission",
                       detail: "Expands island when Claude needs approval") {
                Toggle("", isOn: $autoExpand).labelsHidden().toggleStyle(.switch)
            }

            SettingRow(label: "Session idle timeout",
                       detail: "Minutes before idle sessions disappear") {
                Stepper("\(idleTimeout) min", value: $idleTimeout, in: 1...60)
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.7))
            }

            Divider().background(Color.white.opacity(0.08))

            HStack(spacing: 4) {
                Text("Claude Monitor v1.0  ·")
                    .font(.system(size: 10)).foregroundColor(.white.opacity(0.2))
                Link("GitHub", destination: URL(string: "https://github.com/alfonsopuicercus/claude-monitor")!)
                    .font(.system(size: 10)).foregroundColor(.white.opacity(0.32))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct SettingRow<C: View>: View {
    let label: String; let detail: String
    @ViewBuilder var control: () -> C
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 12)).foregroundColor(.white.opacity(0.8))
                Text(detail).font(.system(size: 10)).foregroundColor(.white.opacity(0.28))
            }
            Spacer()
            control()
        }
    }
}

// MARK: - Tool badge

struct MiniToolBadge: View {
    let name: String
    var color: Color {
        switch name {
        case "Bash":                return Color(red: 0.25, green: 0.55, blue: 1.0)
        case "Edit", "Write":       return Color(red: 0.70, green: 0.35, blue: 1.0)
        case "Read":                return Color(red: 0.25, green: 0.80, blue: 0.65)
        case "Grep", "Glob":        return Color(red: 0.20, green: 0.72, blue: 0.75)
        case "WebSearch","WebFetch": return Color(red: 1.00, green: 0.55, blue: 0.20)
        case "Subagent":            return Color(red: 0.55, green: 0.45, blue: 1.00)
        default:                    return Color(white: 0.42)
        }
    }
    var body: some View {
        Text(name)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.13))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.32), lineWidth: 0.5))
            .cornerRadius(4)
    }
}

// MARK: - Time helper

private func timeAgo(_ date: Date) -> String {
    let s = Int(-date.timeIntervalSinceNow)
    if s < 5  { return "now" }
    if s < 60 { return "\(s)s" }
    let m = s / 60
    if m < 60 { return "\(m)m" }
    return "\(m/60)h"
}
