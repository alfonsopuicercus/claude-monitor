// claude-monitor-bridge
// Called by Claude Code hooks via stdin with JSON data.
// Forwards hook events to the Claude Monitor app via Unix socket.
// For PermissionRequest: waits for approve/deny response before exiting.

import Foundation

let kSocketPath = "/tmp/claude-monitor.sock"

// MARK: - Read all stdin

var stdinData = Data()
let bufSize = 4096
var buf = [UInt8](repeating: 0, count: bufSize)
while true {
    let n = read(STDIN_FILENO, &buf, bufSize)
    if n <= 0 { break }
    stdinData.append(contentsOf: buf[0..<n])
}

guard !stdinData.isEmpty,
      let hookJSON = try? JSONSerialization.jsonObject(with: stdinData) as? [String: Any] else {
    exit(0)
}

// MARK: - Extract fields

let hookEvent  = hookJSON["hook_event_name"] as? String ?? ""
let sessionId  = hookJSON["session_id"] as? String ?? UUID().uuidString
let toolName   = hookJSON["tool_name"] as? String
let toolInput  = hookJSON["tool_input"] as? [String: Any]
let hookCwd    = hookJSON["cwd"] as? String ?? FileManager.default.currentDirectoryPath
let prompt     = hookJSON["prompt"] as? String
let hookMsg    = hookJSON["message"] as? String

// Terminal identity from environment
let env = ProcessInfo.processInfo.environment
var terminal: [String: Any] = [:]
if let v = env["TERM_PROGRAM"]    { terminal["termProgram"]    = v }
if let v = env["TERM_SESSION_ID"] { terminal["termSessionId"]  = v }
if let v = env["ITERM_SESSION_ID"]{ terminal["itermSessionId"] = v }
if let v = env["WEZTERM_PANE"]    { terminal["weztermPane"]    = v }
if let v = env["TMUX_PANE"]       { terminal["tmuxPane"]       = v }

// Get TTY name
if let rawPtr = ttyname(STDIN_FILENO), let ttyStr = String(validatingUTF8: rawPtr) {
    terminal["tty"] = ttyStr
}

// MARK: - Build message for the app

var outMsg: [String: Any] = [
    "sessionId": sessionId,
    "hookEvent": hookEvent,
    "cwd":       hookCwd,
    "source":    "claude",
    "terminal":  terminal,
    "timestamp": Date().timeIntervalSinceReferenceDate,
    "hookData":  hookJSON,
]
if let v = toolName  { outMsg["toolName"]  = v }
if let v = toolInput { outMsg["toolInput"] = v }
if let v = prompt    { outMsg["prompt"]    = v }
if let v = hookMsg   { outMsg["message"]   = v }

guard let outData = try? JSONSerialization.data(withJSONObject: outMsg) else { exit(0) }

// MARK: - Connect to socket

func openSocket(path: String) -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return -1 }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: Int8.self, capacity: 104) { p in
            _ = strncpy(p, path, 103)
        }
    }
    let rc = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    if rc != 0 { close(fd); return -1 }
    return fd
}

let fd = openSocket(path: kSocketPath)
if fd < 0 {
    // App not running — allow by default for permission requests
    if hookEvent == "PermissionRequest" {
        print("{\"continue\":true}")
    }
    exit(0)
}

// MARK: - Send message

var payload = outData
payload.append(contentsOf: [UInt8]("\n".utf8))
var sent = 0
while sent < payload.count {
    let n = payload.withUnsafeBytes { ptr in
        send(fd, ptr.baseAddress!.advanced(by: sent), ptr.count - sent, 0)
    }
    if n <= 0 { break }
    sent += n
}

// MARK: - Wait for response (PermissionRequest only)

if hookEvent == "PermissionRequest" {
    // Set 24-hour receive timeout
    var tv = timeval(tv_sec: 86400, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    var responseData = Data()
    var responseBuf = [UInt8](repeating: 0, count: 4096)
    outer: while true {
        let n = recv(fd, &responseBuf, responseBuf.count, 0)
        if n <= 0 { break }
        responseData.append(contentsOf: responseBuf[0..<n])
        if let _ = try? JSONSerialization.jsonObject(with: responseData) { break outer }
    }
    close(fd)

    if let respJSON = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
        let shouldContinue = respJSON["continue"] as? Bool ?? true
        if shouldContinue {
            print("{\"continue\":true}")
            exit(0)
        } else {
            let reason = respJSON["reason"] as? String ?? "Denied via Claude Monitor"
            let blocked: [String: Any] = ["continue": false, "reason": reason]
            if let d = try? JSONSerialization.data(withJSONObject: blocked),
               let s = String(data: d, encoding: .utf8) {
                print(s)
            }
            exit(2)
        }
    } else {
        // No response / timeout — allow by default
        print("{\"continue\":true}")
        exit(0)
    }
} else {
    close(fd)
    exit(0)
}
