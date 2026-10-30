import Foundation
import os

final class PiRPCClient: @unchecked Sendable {
    nonisolated private static let logger = Logger(subsystem: "streetcoding.agent-deck", category: "PiRPC")
    struct EventLine: Sendable {
        let rawLine: String
        let event: PiAgentRPCEvent?
    }

    typealias EventHandler = @Sendable (_ lines: [EventLine]) -> Void
    typealias StderrHandler = @Sendable (_ lines: [String]) -> Void
    typealias TerminationHandler = @Sendable (_ exitCode: Int32) -> Void

    private let process: PiAgentProcess
    private let encoder = JSONEncoder()
    private let responses = PiRPCResponseTracker()
    let supportsSettledEvent: Bool

    var launchCommand: String { process.launchCommand }
    var isRunning: Bool { process.isRunning }

    init(
        cwd: URL,
        sessionFile: String? = nil,
        provider: String? = nil,
        model: String? = nil,
        modelArgument: String? = nil,
        thinkingLevel: String? = nil,
        extraArguments: [String] = [],
        environment: [String: String] = [:],
        onEvent: @escaping EventHandler,
        onStderr: @escaping StderrHandler,
        onTermination: @escaping TerminationHandler
    ) throws {
        let tracker = responses
        supportsSettledEvent = PiExecutableResolver().resolve().map { PiExecutableResolver.supportsSettledEvent(piPath: $0.path) } ?? false
        let args = Self.launchArguments(
            sessionFile: sessionFile,
            provider: provider,
            model: model,
            modelArgument: modelArgument,
            thinkingLevel: thinkingLevel,
            extraArguments: extraArguments
        )

        process = try PiAgentProcess(
            configuration: .init(arguments: args, currentDirectoryURL: cwd, environment: environment),
            onStdoutLines: { lines in
                let events = lines.compactMap { line -> EventLine? in
                    let data = Data(line.utf8)
                    let event = try? JSONDecoder().decode(PiAgentRPCEvent.self, from: data)
                    if let event, !tracker.shouldDeliver(event) { return nil }
                    return EventLine(rawLine: line, event: event)
                }
                if !events.isEmpty { onEvent(events) }
            },
            onStderrLines: onStderr,
            onTermination: onTermination
        )
    }

    static func launchArguments(
        sessionFile: String? = nil,
        provider: String? = nil,
        model: String? = nil,
        modelArgument: String? = nil,
        thinkingLevel: String? = nil,
        extraArguments: [String] = []
    ) -> [String] {
        var args = ["--mode", "rpc"]
        args.append(contentsOf: extraArguments)
        if let sessionFile, !sessionFile.isEmpty {
            args.append(contentsOf: ["--session", sessionFile])
        }
        if let provider, !provider.isEmpty {
            args.append(contentsOf: ["--provider", provider])
        }
        if let modelArgument, !modelArgument.isEmpty {
            args.append(contentsOf: ["--model", modelArgument])
        } else if let model, !model.isEmpty {
            args.append(contentsOf: ["--model", model])
        }
        if let thinkingLevel, !thinkingLevel.isEmpty {
            args.append(contentsOf: ["--thinking", thinkingLevel])
        }
        return args
    }

    func getState() { send(type: "get_state") }
    @discardableResult func getMessages() -> String { send(type: "get_messages") }
    @discardableResult func getSessionStats() -> String { send(type: "get_session_stats") }
    func getCommands() { send(type: "get_commands") }
    func abort() { send(type: "abort") }
    func setSessionName(_ name: String) { send(type: "set_session_name", fields: ["name": name]) }
    func setModel(provider: String, modelID: String) { send(type: "set_model", fields: ["provider": provider, "modelId": modelID]) }
    func cycleModel() { send(type: "cycle_model") }
    func setThinkingLevel(_ level: String) { send(type: "set_thinking_level", fields: ["level": level]) }
    func cycleThinkingLevel() { send(type: "cycle_thinking_level") }
    func compact(customInstructions: String? = nil) {
        var fields: [String: Any] = [:]
        if let customInstructions, !customInstructions.isEmpty {
            fields["customInstructions"] = customInstructions
        }
        send(type: "compact", fields: fields)
    }
    func fork(entryId: String) { send(type: "fork", fields: ["entryId": entryId]) }
    func getForkMessages() { send(type: "get_fork_messages") }
    func prompt(_ message: String, images: [PiAgentImageAttachment] = [], streamingBehavior: String? = nil) {
        sendUserMessage(type: "prompt", message: message, images: images, streamingBehavior: streamingBehavior)
    }
    func steer(_ message: String, images: [PiAgentImageAttachment] = []) { sendUserMessage(type: "steer", message: message, images: images) }
    func followUp(_ message: String, images: [PiAgentImageAttachment] = []) { sendUserMessage(type: "follow_up", message: message, images: images) }
    func respondToExtensionUI(id: String, value: String) { sendExtensionUIResponse(["id": id, "value": value]) }
    func confirmExtensionUI(id: String, confirmed: Bool) { sendExtensionUIResponse(["id": id, "confirmed": confirmed]) }
    func cancelExtensionUI(id: String) { sendExtensionUIResponse(["id": id, "cancelled": true]) }

    private func sendUserMessage(type: String, message: String, images: [PiAgentImageAttachment], streamingBehavior: String? = nil) {
        var fields: [String: Any] = ["message": message]
        if let streamingBehavior {
            fields["streamingBehavior"] = streamingBehavior
        }
        if !images.isEmpty {
            fields["images"] = images.map(\.rpcPayload)
        }
        send(type: type, fields: fields)
    }

    @discardableResult func send(type: String, fields: [String: Any] = [:]) -> String {
        let requestID = responses.register(type: type)

        var command = fields
        command["id"] = requestID
        command["type"] = type
        write(command)
        return requestID
    }

    private func sendExtensionUIResponse(_ fields: [String: Any]) {
        var command = fields
        command["type"] = "extension_ui_response"
        write(command)
    }

    private func write(_ command: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(command),
              let data = try? JSONSerialization.data(withJSONObject: command),
              let line = String(data: data, encoding: .utf8) else { return }
#if DEBUG
        let type = command["type"] as? String ?? "unknown"
        // Routine polling fires several times a second during streaming and drowns the
        // meaningful commands (prompt/abort/set_session_name/extension responses). Skip it.
        let routinePolling: Set<String> = ["get_state", "get_session_stats", "get_commands"]
        if !routinePolling.contains(type) {
            let requestID = command["id"] as? String ?? "extension-ui"
            let streamingBehavior = command["streamingBehavior"] as? String ?? ""
            Self.logger.info("Sending RPC command type=\(type, privacy: .public) id=\(requestID, privacy: .public) hasMessage=\(command["message"] != nil) hasImages=\(command["images"] != nil) streamingBehavior=\(streamingBehavior, privacy: .public)")
        }
#endif
        process.writeJSONLine(line)
    }

    func stop() {
        abort()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { [process] in
            process.terminate()
        }
    }
}

/// Responses can arrive out of order. Discard superseded snapshots and model or
/// thinking selections; legacy responses without IDs remain supported.
nonisolated final class PiRPCResponseTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var counter = 0
    private var lastDelivered: [String: Int] = [:]
    private func group(for type: String) -> String? {
        switch type {
        case "get_state", "get_messages", "get_session_stats", "get_commands": return type
        case "set_model", "cycle_model": return "model_selection"
        case "set_thinking_level", "cycle_thinking_level": return "thinking_selection"
        default: return nil
        }
    }

    func register(type: String) -> String {
        lock.lock(); defer { lock.unlock() }
        counter += 1
        if group(for: type) == "model_selection" || group(for: type) == "thinking_selection" {
            lastDelivered["get_state"] = counter
        }
        return "pm-\(counter)"
    }

    func shouldDeliver(_ event: PiAgentRPCEvent) -> Bool {
        guard event.type == "response", let command = event.command, let group = group(for: command),
              let id = event.id, id.hasPrefix("pm-"), let number = Int(id.dropFirst(3)) else { return true }
        lock.lock(); defer { lock.unlock() }
        guard number >= (lastDelivered[group] ?? 0) else { return false }
        lastDelivered[group] = number
        return true
    }
}
