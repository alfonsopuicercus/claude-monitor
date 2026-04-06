// DynamicIslandView.swift
// The pill-shaped floating overlay inspired by iPhone Dynamic Island.
// Click to expand/collapse. Permission requests auto-expand with orange glow.

import SwiftUI
import AppKit

struct DynamicIslandView: View {
    @ObservedObject var store: SessionStore
    weak var window: DynamicIslandWindow?

    @State private var expanded = false
    @State private var glowOpacity: Double = 0
    @State private var glowScale: CGFloat = 1.0

    private var hasPermissionPending: Bool {
        store.totalPermissionsWaiting > 0
    }

    private var pillColor: Color {
        hasPermissionPending ? Color(red: 0.15, green: 0.08, blue: 0.0) : Color(white: 0.08)
    }

    private var glowColor: Color {
        hasPermissionPending ? .orange : .green
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Outer container — transparent, fills the window
            Color.clear

            // The island pill
            VStack(spacing: 0) {
                if expanded {
                    expandedContent
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal:   .opacity.combined(with: .move(edge: .top))
                        ))
                } else {
                    collapsedContent
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, expanded ? 14 : 16)
            .padding(.vertical, expanded ? 12 : 0)
            .frame(minHeight: DynamicIslandWindow.collapsedSize.height)
            .background(
                ZStack {
                    // Glow
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(glowColor.opacity(0.35))
                        .blur(radius: 16)
                        .scaleEffect(glowScale)
                        .opacity(glowOpacity)

                    // Main pill background
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(pillColor)

                    // Subtle inner border
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.15), Color.white.opacity(0.04)],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                }
                .shadow(color: Color.black.opacity(0.5), radius: 20, y: 8)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .onTapGesture { toggleExpanded() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: hasPermissionPending) { pending in
            if pending && !expanded {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                    expanded = true
                }
                updateWindowSize(expanded: true)
            }
            withAnimation(.easeInOut(duration: 0.3)) {
                glowOpacity = pending ? 1.0 : (store.sessions.contains { $0.status == .working } ? 0.4 : 0)
            }
            if pending { pulseGlow() }
        }
        .onChange(of: store.sessions.count) { _ in
            updateGlow()
            if expanded { updateWindowSize(expanded: true) }
        }
        .onChange(of: store.sessions.map(\.status.rawValue).joined()) { _ in
            // Auto-collapse if all sessions are idle and no permission pending
            if expanded && !hasPermissionPending &&
               store.sessions.allSatisfy({ $0.status == .idle || $0.status == .working }) {
                // keep expanded — only collapse on explicit tap
            }
            if expanded { updateWindowSize(expanded: true) }
        }
        .onAppear {
            updateGlow()
        }
    }

    // MARK: - Collapsed pill

    private var collapsedContent: some View {
        HStack(spacing: 8) {
            // Status indicator
            statusIndicator

            // Session summary
            if store.sessions.isEmpty {
                Text("Claude Monitor")
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .foregroundColor(.white.opacity(0.5))
            } else if hasPermissionPending {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text(permissionSummary)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)
                }
            } else {
                Text(sessionSummary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Right: current tool badge or session count
            if let tool = activeTool {
                MiniToolBadge(name: tool)
            } else if !store.sessions.isEmpty {
                Text("\(store.sessions.count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(minWidth: 16)
            }
        }
        .frame(height: DynamicIslandWindow.collapsedSize.height)
    }

    // MARK: - Expanded content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top bar with title + collapse button
            HStack {
                HStack(spacing: 6) {
                    statusIndicator
                    Text("Claude Monitor")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                Spacer()
                Button(action: { toggleExpanded() }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)

            if store.sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
    }

    // MARK: - Session list

    private var sortedSessions: [ClaudeSession] {
        store.sessions.sorted {
            if $0.status == .waitingForPermission && $1.status != .waitingForPermission { return true }
            if $0.status != .waitingForPermission && $1.status == .waitingForPermission { return false }
            return $0.lastActivityAt > $1.lastActivityAt
        }
    }

    private var sessionList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(sortedSessions) { session in
                    SessionCard(session: session, store: store)
                }
            }
        }
        .frame(maxHeight: 420)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 5) {
                Image(systemName: "terminal")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.2))
                Text("No active sessions")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }

    // MARK: - Status indicator dot

    private var statusIndicator: some View {
        ZStack {
            Circle()
                .fill(indicatorColor.opacity(0.3))
                .frame(width: 14, height: 14)
            Circle()
                .fill(indicatorColor)
                .frame(width: 7, height: 7)
        }
    }

    private var indicatorColor: Color {
        if hasPermissionPending           { return .orange }
        if store.sessions.contains(where: { $0.status == .working }) { return .green }
        if store.sessions.isEmpty          { return Color(white: 0.3) }
        return .gray
    }

    // MARK: - Helpers

    private var sessionSummary: String {
        if let working = store.sessions.first(where: { $0.status == .working }) {
            if let tool = working.currentTool {
                return "\(tool) · \(working.displayCwd)"
            }
            if let msg = working.lastUserMessage {
                let shortened = msg.prefix(40)
                return String(shortened) + (msg.count > 40 ? "…" : "")
            }
            return working.displayCwd
        }
        if let idle = store.sessions.first {
            return idle.displayCwd
        }
        return ""
    }

    private var permissionSummary: String {
        let count = store.totalPermissionsWaiting
        if count == 1, let s = store.sessions.first(where: { $0.status == .waitingForPermission }),
           let perm = s.pendingPermission {
            return "\(perm.toolName) needs approval"
        }
        return "\(count) permission\(count == 1 ? "" : "s") pending"
    }

    private var activeTool: String? {
        store.sessions.first(where: { $0.currentTool != nil })?.currentTool
    }

    // MARK: - Expand / collapse

    private func toggleExpanded() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) {
            expanded.toggle()
        }
        updateWindowSize(expanded: expanded)
    }

    private func updateWindowSize(expanded: Bool) {
        guard let window else { return }
        let targetSize: CGSize
        if expanded {
            let sessionCount = store.sessions.count
            let baseHeight: CGFloat = 80                            // header + padding
            let perSession: CGFloat = hasPermissionPending ? 165 : 110
            let estimated = baseHeight + CGFloat(max(sessionCount, 1)) * perSession
            let clampedHeight = min(estimated, 500)
            targetSize = CGSize(width: DynamicIslandWindow.expandedWidth, height: clampedHeight)
        } else {
            targetSize = DynamicIslandWindow.collapsedSize
        }
        window.resize(to: targetSize, animated: true)
    }

    // MARK: - Glow

    private func updateGlow() {
        withAnimation(.easeInOut(duration: 0.4)) {
            glowOpacity = hasPermissionPending ? 1.0
                : store.sessions.contains(where: { $0.status == .working }) ? 0.5
                : 0
        }
    }

    private func pulseGlow() {
        withAnimation(.easeInOut(duration: 0.5).repeatCount(3, autoreverses: true)) {
            glowScale = 1.15
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 0.3)) { glowScale = 1.0 }
        }
    }
}

// MARK: - Session card

struct SessionCard: View {
    let session: ClaudeSession
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: CWD + tool badge
            HStack(spacing: 6) {
                Text(session.statusDot)
                    .font(.system(size: 9))
                    .foregroundColor(Color(session.statusColor))

                Text(session.displayCwd)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let tool = session.currentTool {
                    MiniToolBadge(name: tool)
                }

                Spacer()

                Text(timeAgo(session.lastActivityAt))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }

            // Row 2: last message
            if let msg = session.lastUserMessage ?? session.lastAssistantMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(2)
            }

            // Permission request
            if session.status == .waitingForPermission, let perm = session.pendingPermission {
                PermissionRow(session: session, perm: perm, store: store)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(session.status == .waitingForPermission
                    ? Color.orange.opacity(0.12)
                    : Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            session.status == .waitingForPermission
                                ? Color.orange.opacity(0.35)
                                : Color.white.opacity(0.07),
                            lineWidth: 0.5
                        )
                )
        )
    }
}

// MARK: - Permission row inside card

struct PermissionRow: View {
    let session: ClaudeSession
    let perm: PermissionRequest
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                Text(perm.toolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)
                Spacer()
            }

            if perm.toolInput != "{}" {
                Text(perm.toolInput)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(3)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
            }

            HStack(spacing: 8) {
                Button(action: { store.denyPermission(sessionId: session.id) }) {
                    Label("Deny", systemImage: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: { store.approvePermission(sessionId: session.id) }) {
                    Label("Approve", systemImage: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Mini tool badge (dark theme)

struct MiniToolBadge: View {
    let name: String

    var color: Color {
        switch name {
        case "Bash":      return Color(red: 0.2, green: 0.5, blue: 1.0)
        case "Edit", "Write": return Color(red: 0.7, green: 0.3, blue: 1.0)
        case "Read":      return Color(red: 0.2, green: 0.8, blue: 0.6)
        case "Grep", "Glob": return Color(red: 0.2, green: 0.7, blue: 0.7)
        case "WebSearch", "WebFetch": return Color(red: 1.0, green: 0.5, blue: 0.2)
        case "Subagent":  return Color(red: 0.5, green: 0.4, blue: 1.0)
        default:          return Color(white: 0.4)
        }
    }

    var body: some View {
        Text(name)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(color.opacity(0.4), lineWidth: 0.5)
            )
            .cornerRadius(5)
    }
}

// MARK: - Time helper

private func timeAgo(_ date: Date) -> String {
    let s = Int(-date.timeIntervalSinceNow)
    if s < 5  { return "now" }
    if s < 60 { return "\(s)s" }
    let m = s / 60
    if m < 60 { return "\(m)m" }
    return "\(m / 60)h"
}
