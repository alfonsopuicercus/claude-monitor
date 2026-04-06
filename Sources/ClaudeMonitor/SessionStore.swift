// SessionStore.swift
// Observable store for Claude session state.
// Runs a background Unix socket server using GCD to avoid blocking the main actor.

import Foundation
import AppKit
import AVFoundation

// MARK: - Notification names

extension Notification.Name {
    static let storeDidUpdate = Notification.Name("ClaudeMonitorStoreDidUpdate")
}

// MARK: - Data models

struct ClaudeSession: Identifiable, Codable {
    var id: String
    var cwd: String
    var source: String
    var status: SessionStatus
    var currentTool: String?
    var lastToolInput: String?
    var lastUserMessage: String?
    var lastAssistantMessage: String?
    var firstUserMessage: String?
    var lastActivityAt: Date
    var startedAt: Date
    var termProgram: String?
    var tty: String?
    var pendingPermission: PermissionRequest?

    enum SessionStatus: String, Codable {
        case working
        case waitingForPermission = "waiting_for_approval"
        case idle
    }

    var displayCwd: String {
        cwd.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    var statusColor: NSColor {
        switch status {
        case .working:              return .systemGreen
        case .waitingForPermission: return .systemOrange
        case .idle:                 return .systemGray
        }
    }

    var statusDot: String {
        switch status {
        case .working:              return "●"
        case .waitingForPermission: return "⚠"
        case .idle:                 return "○"
        }
    }
}

struct PermissionRequest: Codable {
    var requestId: String
    var toolName: String
    var toolInput: String
    var receivedAt: Date
}

// MARK: - Paths

private let kSocketPath = "/tmp/claude-monitor.sock"
private let kStoragePath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/ClaudeMonitor/sessions.json")

// MARK: - SessionStore

final class SessionStore: ObservableObject {

    @Published var sessions: [ClaudeSession] = []
    @Published var totalPermissionsWaiting: Int = 0

    /// sessionId → open fd waiting for a permission response
    private var pendingPermissionFDs: [String: Int32] = [:]

    private let acceptQueue = DispatchQueue(label: "com.claude-monitor.accept", qos: .background)
    private let clientQueue = DispatchQueue(label: "com.claude-monitor.clients",
                                            qos: .background, attributes: .concurrent)

    // MARK: Sound

    private func playSound(_ name: NSSound.Name) {
        guard UserDefaults.standard.bool(forKey: "claudeMonitor.soundEnabled") != false else { return }
        NSSound(named: name)?.play()
    }

    // MARK: Init

    init() {
        loadFromDisk()
        startSocketServer()
        // Prune idle sessions periodically
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.pruneDeadSessions()
        }
    }

    // MARK: Persistence

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: kStoragePath),
              let decoded = try? JSONDecoder().decode([ClaudeSession].self, from: data) else { return }
        // Sessions from previous runs can't be resumed — reset to idle.
        // "working" means the old Claude process is gone; "waitingForPermission"
        // means the bridge fd is gone so we can't respond.
        sessions = decoded.map { s in
            var s = s
            if s.status == .waitingForPermission || s.status == .working {
                s.status = .idle
                s.pendingPermission = nil
                s.currentTool = nil
            }
            return s
        }
        recalcPermissions()
    }

    private func saveToDisk() {
        // Must be called on main thread
        try? FileManager.default.createDirectory(
            at: kStoragePath.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(sessions) {
            try? data.write(to: kStoragePath, options: .atomic)
        }
    }

    // MARK: Session updates (call on main thread)

    private func upsertSession(id: String, update: (inout ClaudeSession) -> Void) {
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            update(&sessions[idx])
        } else {
            var s = ClaudeSession(
                id: id,
                cwd: "",
                source: "claude",
                status: .idle,
                lastActivityAt: Date(),
                startedAt: Date()
            )
            update(&s)
            sessions.append(s)
        }
        recalcPermissions()
        saveToDisk()
        NotificationCenter.default.post(name: .storeDidUpdate, object: nil)
    }

    func removeSession(id: String) {
        sessions.removeAll { $0.id == id }
        recalcPermissions()
        saveToDisk()
        NotificationCenter.default.post(name: .storeDidUpdate, object: nil)
    }

    private func recalcPermissions() {
        totalPermissionsWaiting = sessions.filter { $0.status == .waitingForPermission }.count
    }

    private func pruneDeadSessions() {
        let idleCutoff = Date().addingTimeInterval(-300)         // 5 min idle → remove
        let permCutoff = Date().addingTimeInterval(-3600)        // 1 h stale permission → remove
        sessions.removeAll {
            if $0.status == .idle && $0.lastActivityAt < idleCutoff { return true }
            // Stale permission request with no live bridge fd → remove
            if $0.status == .waitingForPermission,
               let receivedAt = $0.pendingPermission?.receivedAt,
               receivedAt < permCutoff,
               pendingPermissionFDs[$0.id] == nil { return true }
            return false
        }
        recalcPermissions()
        saveToDisk()
        NotificationCenter.default.post(name: .storeDidUpdate, object: nil)
    }

    // MARK: Permission responses

    func approvePermission(sessionId: String) {
        sendPermissionResponse(sessionId: sessionId, allow: true, reason: nil)
    }

    func denyPermission(sessionId: String) {
        sendPermissionResponse(sessionId: sessionId, allow: false, reason: nil)
    }

    /// Approve with a custom instruction injected as a "reason" for Claude to read.
    func approveWithInstruction(sessionId: String, instruction: String) {
        sendPermissionResponse(sessionId: sessionId, allow: true, reason: instruction.isEmpty ? nil : instruction)
    }

    private func sendPermissionResponse(sessionId: String, allow: Bool, reason: String?) {
        // Send to bridge if the connection is still live
        if let fd = pendingPermissionFDs[sessionId] {
            var resp: [String: Any] = ["continue": allow]
            if !allow { resp["reason"] = reason ?? "Denied via Claude Monitor" }
            else if let r = reason, !r.isEmpty { resp["reason"] = r }
            if let data = try? JSONSerialization.data(withJSONObject: resp) {
                var payload = data
                payload.append(contentsOf: [UInt8]("\n".utf8))
                payload.withUnsafeBytes { send(fd, $0.baseAddress!, $0.count, 0) }
            }
            close(fd)
            pendingPermissionFDs.removeValue(forKey: sessionId)
        }
        // Always clear the permission UI, whether or not the bridge is still alive
        upsertSession(id: sessionId) { s in
            s.status = allow ? .working : .idle
            s.pendingPermission = nil
            s.lastActivityAt = Date()
        }
    }

    // MARK: Hook event processing (called on background queue, dispatches to main)

    private func processEvent(msg: [String: Any], fd: Int32) {
        let sessionId = msg["sessionId"] as? String ?? UUID().uuidString
        let hookEvent  = msg["hookEvent"] as? String ?? ""
        let cwd        = msg["cwd"] as? String ?? ""
        let source     = msg["source"] as? String ?? "claude"
        let toolName   = msg["toolName"] as? String
        let toolInput  = msg["toolInput"] as? [String: Any]
        let termInfo   = msg["terminal"] as? [String: Any]
        let prompt     = msg["prompt"] as? String
        let message    = msg["message"] as? String

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.upsertSession(id: sessionId) { s in
                s.cwd = cwd
                s.source = source
                s.lastActivityAt = Date()
                if let v = termInfo?["termProgram"] as? String { s.termProgram = v }
                if let v = termInfo?["tty"] as? String { s.tty = v }

                switch hookEvent {
                case "SessionStart":
                    s.status = .idle
                    s.startedAt = Date()
                    s.currentTool = nil
                    s.pendingPermission = nil

                case "SessionEnd":
                    s.status = .idle
                    s.currentTool = nil

                case "UserPromptSubmit":
                    s.status = .working
                    s.currentTool = nil
                    if let p = prompt {
                        let maxLen = 120
                        let trimmed = p.count > maxLen ? String(p.prefix(maxLen)) + "…" : p
                        s.lastUserMessage = trimmed
                        if s.firstUserMessage == nil { s.firstUserMessage = trimmed }
                    }

                case "PreToolUse":
                    s.status = .working
                    s.currentTool = toolName
                    if let inp = toolInput,
                       let d = try? JSONSerialization.data(withJSONObject: inp),
                       let str = String(data: d, encoding: .utf8) {
                        s.lastToolInput = str.count > 300 ? String(str.prefix(300)) + "…" : str
                    }

                case "PostToolUse", "PostToolUseFailure":
                    s.status = .working
                    s.currentTool = nil

                case "Stop", "StopFailure":
                    s.status = .idle
                    s.currentTool = nil

                case "PermissionRequest":
                    s.status = .waitingForPermission
                    let inputStr: String
                    if let inp = toolInput,
                       let d = try? JSONSerialization.data(withJSONObject: inp, options: .prettyPrinted),
                       let str = String(data: d, encoding: .utf8) {
                        inputStr = str
                    } else { inputStr = "{}" }
                    s.pendingPermission = PermissionRequest(
                        requestId: UUID().uuidString,
                        toolName: toolName ?? "Unknown",
                        toolInput: inputStr,
                        receivedAt: Date()
                    )

                case "Notification":
                    if let m = message {
                        s.lastAssistantMessage = m.count > 120 ? String(m.prefix(120)) + "…" : m
                    }

                case "SubagentStart":
                    s.status = .working
                    if s.currentTool == nil { s.currentTool = "Subagent" }

                case "SubagentStop":
                    if s.currentTool == "Subagent" { s.currentTool = nil }

                default:
                    break
                }
            }

            // Sound notifications
            switch hookEvent {
            case "PermissionRequest":
                self.playSound(.init("Funk"))          // urgent ping for approval needed
            case "SessionStart":
                self.playSound(.init("Tink"))          // subtle chime for new session
            case "Stop":
                self.playSound(.init("Glass"))         // soft chime when task completes
            default:
                break
            }

            // Hold the fd open for permission requests so we can send the response later
            if hookEvent == "PermissionRequest" {
                self.pendingPermissionFDs[sessionId] = fd
            }
        }
    }

    // MARK: Socket server (GCD, fully background)

    private func startSocketServer() {
        acceptQueue.async { [weak self] in
            self?.runAcceptLoop()
        }
    }

private func runAcceptLoop() {
        // Remove stale socket file
        try? FileManager.default.removeItem(atPath: kSocketPath)

        let serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            print("[ClaudeMonitor] socket() failed: \(errno)")
            return
        }
        var reuseAddr: Int32 = 1
        setsockopt(serverFd, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: Int8.self, capacity: 104) { p in
                _ = strncpy(p, kSocketPath, 103)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            print("[ClaudeMonitor] bind() failed: \(errno)")
            close(serverFd)
            return
        }

        guard listen(serverFd, 32) == 0 else {
            print("[ClaudeMonitor] listen() failed: \(errno)")
            close(serverFd)
            return
        }

        print("[ClaudeMonitor] Listening on \(kSocketPath)")

        while true {
            let clientFd = accept(serverFd, nil, nil)
            if clientFd < 0 { continue }
            clientQueue.async { [weak self] in
                self?.handleClient(fd: clientFd)
            }
        }
    }

    private func handleClient(fd: Int32) {
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 8192)

        // Read until we get valid JSON
        while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n < 0 { close(fd); return }
            if n == 0 { break }
            data.append(contentsOf: buf[0..<n])
            if let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let hookEvent = msg["hookEvent"] as? String ?? ""
                processEvent(msg: msg, fd: fd)
                // For non-permission events, close immediately
                if hookEvent != "PermissionRequest" {
                    close(fd)
                }
                return
            }
        }
        close(fd)
    }
}
