// DynamicIslandView.swift
// Notch-style overlay attached to the very top of the screen.
// - Collapsed: pill showing status + tool
// - Expanded: session cards with live tool output, settings
// - Idle: animated character ("Claude is resting…")
// - Permission: orange glow + Approve/Deny

import SwiftUI
import AppKit

// MARK: - Root view

struct DynamicIslandView: View {
    @ObservedObject var store: SessionStore
    weak var window: DynamicIslandWindow?

    @State private var expanded = false
    @State private var showSettings = false

    // Glow
    @State private var glowOpacity: Double = 0
    @State private var glowScale: CGFloat = 1.0

    // Idle animation
    @State private var idlePhase: Double = 0
    @State private var eyeBlink = false

    var hasPermission: Bool { store.totalPermissionsWaiting > 0 }
    var isWorking: Bool { store.sessions.contains { $0.status == .working } }
    var isIdle: Bool { !isWorking && !hasPermission }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            VStack(spacing: 0) {
                // ── Collapsed bar (always visible) ──
                collapsedBar
                    .frame(height: DynamicIslandWindow.barHeight)

                // ── Expanded panel ──
                if expanded {
                    Divider()
                        .background(Color.white.opacity(0.08))

                    if showSettings {
                        SettingsPanel(store: store, onDone: { showSettings = false })
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        expandedPanel
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity.combined(with: .move(edge: .top))
                            ))
                    }
                }
            }
            .background(
                ZStack {
                    // Glow halo
                    NotchShape()
                        .fill(glowColor.opacity(0.4))
                        .blur(radius: 20)
                        .scaleEffect(glowScale)
                        .opacity(glowOpacity)

                    // Notch body
                    NotchShape()
                        .fill(Color(white: 0.07))

                    // Top highlight
                    NotchShape()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.12), Color.white.opacity(0.0)],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                }
                .shadow(color: Color.black.opacity(0.6), radius: 18, y: 6)
            )
            .clipShape(NotchShape())
            .contentShape(NotchShape())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Idle animation timer
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: true)) {
                idlePhase = 1
            }
            Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.12)) { eyeBlink = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeInOut(duration: 0.12)) { eyeBlink = false }
                }
            }
            updateGlow()
        }
        .onChange(of: hasPermission) { pending in
            if pending && !expanded {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) { expanded = true }
                updateWindowSize(expanded: true)
            }
            withAnimation(.easeInOut(duration: 0.35)) { glowOpacity = pending ? 1 : (isWorking ? 0.45 : 0) }
            if pending { pulseGlow() }
        }
        .onChange(of: store.sessions.count) { _ in
            if expanded { updateWindowSize(expanded: true) }
            withAnimation { updateGlow() }
        }
        .onChange(of: store.sessions.map { $0.status.rawValue }.joined()) { _ in
            if expanded { updateWindowSize(expanded: true) }
        }
    }

    // MARK: - Collapsed bar

    private var collapsedBar: some View {
        HStack(spacing: 10) {
            // Left: status dot / character
            if isIdle {
                IdleCharacter(phase: idlePhase, eyeBlink: eyeBlink)
                    .frame(width: 28, height: 22)
            } else {
                StatusDot(color: hasPermission ? .orange : .green, pulsing: isWorking || hasPermission)
                    .frame(width: 18, height: 18)
            }

            // Center: status text
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
                        if let tool = activeTool {
                            MiniToolBadge(name: tool)
                        }
                    }
                } else if !store.sessions.isEmpty {
                    Text("\(store.sessions.count) session\(store.sessions.count == 1 ? "" : "s") idle")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                } else {
                    Text("Claude Monitor")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .lineLimit(1)

            Spacer(minLength: 0)

            // Right: session count + expand chevron
            HStack(spacing: 6) {
                if store.sessions.count > 0 {
                    Text("\(store.sessions.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 16)
        .onTapGesture { toggleExpanded() }
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
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 420)
            }

            // Footer
            HStack {
                Button(action: { withAnimation { showSettings.toggle() } }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            IdleCharacter(phase: idlePhase, eyeBlink: eyeBlink)
                .frame(width: 48, height: 38)
            Text("No sessions running")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.3))
            Text("Start Claude Code to see activity here.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .foregroundColor(.white.opacity(0.2))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Helpers

    private var sortedSessions: [ClaudeSession] {
        store.sessions.sorted {
            if $0.status == .waitingForPermission && $1.status != .waitingForPermission { return true }
            if $0.status != .waitingForPermission && $1.status == .waitingForPermission { return false }
            return $0.lastActivityAt > $1.lastActivityAt
        }
    }

    private var activeTool: String? {
        store.sessions.first(where: { $0.currentTool != nil })?.currentTool
    }

    private var permissionLabel: String {
        let n = store.totalPermissionsWaiting
        if n == 1, let s = store.sessions.first(where: { $0.status == .waitingForPermission }),
           let p = s.pendingPermission {
            return "\(p.toolName) needs approval"
        }
        return "\(n) approvals needed"
    }

    private var glowColor: Color {
        hasPermission ? .orange : .green
    }

    private func updateGlow() {
        glowOpacity = hasPermission ? 1.0 : (isWorking ? 0.45 : 0)
    }

    private func pulseGlow() {
        withAnimation(.easeInOut(duration: 0.45).repeatCount(3, autoreverses: true)) { glowScale = 1.12 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.25)) { glowScale = 1.0 }
        }
    }

    private func toggleExpanded() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) { expanded.toggle() }
        updateWindowSize(expanded: expanded)
    }

    private func updateWindowSize(expanded: Bool) {
        guard let window else { return }
        if !expanded {
            window.resize(to: DynamicIslandWindow.collapsedSize, animated: true)
            return
        }
        let sessions = store.sessions
        let base: CGFloat = DynamicIslandWindow.barHeight + 50   // bar + footer
        let perSession: CGFloat = 105
        let permExtra: CGFloat = hasPermission ? 70 : 0
        let empty: CGFloat = 100
        let content = sessions.isEmpty
            ? empty
            : CGFloat(sessions.count) * perSession + permExtra
        let h = min(base + content, 560)
        window.resize(to: CGSize(width: DynamicIslandWindow.expandedWidth, height: h), animated: true)
    }
}

// MARK: - Notch shape (attached to top, curved bottom corners)

struct NotchShape: Shape {
    var cornerRadius: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Top-left: square (attached to screen edge)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Top-right: square
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Right side down to bottom-right curve
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        // Bottom-right corner (rounded)
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        // Bottom edge
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        // Bottom-left corner (rounded)
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        // Left side back to top
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Pulsing status dot

struct StatusDot: View {
    let color: Color
    let pulsing: Bool
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.25)).scaleEffect(scale)
            Circle().fill(color).frame(width: 7, height: 7)
        }
        .onAppear {
            guard pulsing else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                scale = 1.6
            }
        }
    }
}

// MARK: - Idle character (tiny animated face)

struct IdleCharacter: View {
    var phase: Double   // 0…1, loops
    var eyeBlink: Bool

    var floatOffset: CGFloat { CGFloat(sin(phase * .pi)) * 2.5 }

    var body: some View {
        ZStack {
            // Body (rounded square)
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(white: 0.18))
                .frame(width: 22, height: 22)
                .offset(y: floatOffset)

            // Eyes
            HStack(spacing: 5) {
                Eye(blink: eyeBlink)
                Eye(blink: eyeBlink)
            }
            .offset(y: floatOffset - 1)

            // Tiny antenna
            VStack(spacing: 0) {
                Circle()
                    .fill(Color(white: 0.45))
                    .frame(width: 3, height: 3)
                Rectangle()
                    .fill(Color(white: 0.3))
                    .frame(width: 1.5, height: 6)
            }
            .offset(y: floatOffset - 14)
        }
    }
}

struct Eye: View {
    var blink: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color(white: 0.7))
            .frame(width: 3, height: blink ? 1 : 3)
            .animation(.easeInOut(duration: 0.1), value: blink)
    }
}

// MARK: - Session card

struct SessionCard: View {
    let session: ClaudeSession
    @ObservedObject var store: SessionStore
    @State private var showInput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 6) {
                StatusDot(color: Color(session.statusColor), pulsing: session.status == .working)
                    .frame(width: 14, height: 14)

                Text(session.displayCwd)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let tool = session.currentTool {
                    MiniToolBadge(name: tool)
                }

                Spacer()

                Text(timeAgo(session.lastActivityAt))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(.bottom, 5)

            // Last user message
            if let msg = session.lastUserMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(2)
                    .padding(.bottom, 4)
            }

            // Live tool output (what's running right now)
            if let tool = session.currentTool, let input = session.lastToolInput {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showInput.toggle() } }) {
                    HStack(spacing: 5) {
                        Image(systemName: showInput ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.3))
                        Text("\(tool):")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.35))
                        Text(firstLine(input))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
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
                        .lineLimit(6)
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
                    .padding(.top, 6)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(session.status == .waitingForPermission
                    ? Color.orange.opacity(0.1)
                    : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            session.status == .waitingForPermission
                                ? Color.orange.opacity(0.3)
                                : Color.white.opacity(0.06),
                            lineWidth: 0.5
                        )
                )
        )
    }

    private func firstLine(_ s: String) -> String {
        // For JSON input like {"command":"ls"}, extract the first value
        if let data = s.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let first = obj.values.first as? String {
            return first.components(separatedBy: .newlines).first ?? first
        }
        return s.components(separatedBy: .newlines).first ?? s
    }
}

// MARK: - Permission block

struct PermissionBlock: View {
    let session: ClaudeSession
    let perm: PermissionRequest
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                Text("Permission required — \(perm.toolName)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.orange)
            }

            if perm.toolInput != "{}" {
                Text(perm.toolInput)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(7)
            }

            HStack(spacing: 6) {
                Button(action: { store.denyPermission(sessionId: session.id) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Deny")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.12))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: { store.approvePermission(sessionId: session.id) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Approve")
                            .font(.system(size: 11, weight: .semibold))
                    }
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

// MARK: - Settings panel

struct SettingsPanel: View {
    @ObservedObject var store: SessionStore
    var onDone: () -> Void

    @AppStorage("claudeMonitor.autoExpand") var autoExpand = true
    @AppStorage("claudeMonitor.showCharacter") var showCharacter = true
    @AppStorage("claudeMonitor.idleTimeout") var idleTimeout = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onDone) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }

            Divider().background(Color.white.opacity(0.1))

            SettingRow(label: "Auto-expand on permission",
                       detail: "Expands when Claude needs approval") {
                Toggle("", isOn: $autoExpand).labelsHidden().toggleStyle(.switch)
            }

            SettingRow(label: "Show idle character",
                       detail: "Animated character when no sessions") {
                Toggle("", isOn: $showCharacter).labelsHidden().toggleStyle(.switch)
            }

            SettingRow(label: "Idle session timeout",
                       detail: "Minutes before idle sessions are removed") {
                Stepper("\(idleTimeout) min", value: $idleTimeout, in: 1...60)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
            }

            Divider().background(Color.white.opacity(0.1))

            HStack {
                Text("v1.0 · ")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.2))
                Link("GitHub", destination: URL(string: "https://github.com/alfonsopuicercus/claude-monitor")!)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct SettingRow<Control: View>: View {
    let label: String
    let detail: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }
            Spacer()
            control()
        }
    }
}

// MARK: - Shared tool badge (dark theme)

struct MiniToolBadge: View {
    let name: String
    var color: Color {
        switch name {
        case "Bash":               return Color(red: 0.25, green: 0.55, blue: 1.0)
        case "Edit", "Write":      return Color(red: 0.7,  green: 0.35, blue: 1.0)
        case "Read":               return Color(red: 0.25, green: 0.8,  blue: 0.65)
        case "Grep", "Glob":       return Color(red: 0.2,  green: 0.7,  blue: 0.75)
        case "WebSearch","WebFetch":return Color(red: 1.0,  green: 0.55, blue: 0.2)
        case "Subagent":           return Color(red: 0.55, green: 0.45, blue: 1.0)
        default:                   return Color(white: 0.45)
        }
    }
    var body: some View {
        Text(name)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.13))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.35), lineWidth: 0.5))
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
