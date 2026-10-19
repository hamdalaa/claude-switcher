import ClaudeSwitcherCore
import Foundation
import os

/// Talks to `codex app-server` over stdio: initialize → account/read + account/rateLimits/read.
/// Read-only; no model requests. Runs off the main thread with a hard timeout.
enum CodexReader {
    private static let log = Logger(subsystem: System.subsystem, category: "codex")
    static let timeout: TimeInterval = 15

    enum Failure: LocalizedError {
        case unavailable(String)
        var errorDescription: String? {
            if case .unavailable(let message) = self { return message }
            return nil
        }
    }

    /// Whether the codex CLI is on the user's PATH; the Codex card only shows when it is.
    static func isInstalled() async -> Bool {
        await System.which("codex") != nil
    }

    static func read() async throws -> CodexUsage {
        let env = await System.toolEnvironment()
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let (limits, account) = try exchange(environment: env)
                    continuation.resume(returning: try CodexAPI.parse(limits: limits, account: account))
                } catch {
                    log.notice("codex read failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func exchange(environment: [String: String]) throws -> (limits: Data, account: Data?) {
        let process = Process()
        // The user's PATH so an npm-installed codex finds its node.
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["codex", "app-server", "--stdio"]
        process.environment = environment
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw Failure.unavailable("Codex CLI not found") }

        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        defer {
            killer.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }

        func send(_ value: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: value)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "claude_switcher", "title": "Claude Switcher", "version": "1.0"],
            "capabilities": ["experimentalApi": false],
        ]])

        var pending = Data()
        var limits: Data?
        var account: Data?
        var accountDone = false
        while true {
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { break }   // EOF: process exited or was killed
            pending.append(chunk)
            guard pending.count < 1_000_000 else { throw Failure.unavailable("Codex sent too much data") }
            while let newline = pending.firstIndex(of: 10) {
                let line = pending[..<newline]
                pending.removeSubrange(...newline)
                guard let value = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                      let id = value["id"] as? Int else { continue }
                switch id {
                case 1:
                    try send(["method": "initialized", "params": [:]])
                    try send(["id": 2, "method": "account/rateLimits/read", "params": [:]])
                    try send(["id": 3, "method": "account/read", "params": [:]])
                case 2:
                    guard let result = value["result"] else {
                        let message = (value["error"] as? [String: Any])?["message"] as? String
                        throw Failure.unavailable(message.map { "Codex: \($0)" } ?? "Sign in to Codex (codex login)")
                    }
                    limits = try JSONSerialization.data(withJSONObject: result)
                case 3:
                    accountDone = true
                    if let result = value["result"] { account = try? JSONSerialization.data(withJSONObject: result) }
                default: break
                }
                if let limits, accountDone { return (limits, account) }
            }
        }
        if let limits { return (limits, account) }
        throw Failure.unavailable("Codex didn't answer")
    }
}
