import Foundation
import XCTest
@testable import agent_deck

final class PiCompatibilityTests: XCTestCase {
    func testManagedInstallResolvesCurrentReleaseAndRejectsInvalidMarker() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pi-managed-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        let install = root.appendingPathComponent("install", isDirectory: true)
        let package = install.appendingPathComponent("releases/1.4.0/node_modules/@earendil-works/pi-coding-agent", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: package.appendingPathComponent("dist"), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: bin.appendingPathComponent("pi"), atomically: true, encoding: .utf8)
        try "1.4.0\n".write(to: install.appendingPathComponent("current-version"), atomically: true, encoding: .utf8)
        try "".write(to: package.appendingPathComponent("dist/index.js"), atomically: true, encoding: .utf8)
        try #"{"name":"@earendil-works/pi-coding-agent","version":"1.4.0"}"#.write(to: package.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(PiExecutableResolver.managedPackageRoot(piPath: bin.appendingPathComponent("pi").path)?.standardizedFileURL, package.standardizedFileURL)
        XCTAssertTrue(PiExecutableResolver.supportsSettledEvent(piPath: bin.appendingPathComponent("pi").path))
        try #"{"name":"@earendil-works/pi-coding-agent","version":"0.80.3"}"#.write(to: package.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        XCTAssertFalse(PiExecutableResolver.supportsSettledEvent(piPath: bin.appendingPathComponent("pi").path))
        try #"{"name":"@earendil-works/pi-coding-agent","version":"0.80.4"}"#.write(to: package.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        XCTAssertTrue(PiExecutableResolver.supportsSettledEvent(piPath: bin.appendingPathComponent("pi").path))
        try "../other\n".write(to: install.appendingPathComponent("current-version"), atomically: true, encoding: .utf8)
        XCTAssertNil(PiExecutableResolver.managedPackageRoot(piPath: bin.appendingPathComponent("pi").path))
    }

    func testPollingResponsesAreMatchedToNewestRequest() throws {
        let tracker = PiRPCResponseTracker()
        let first = tracker.register(type: "get_state")
        let second = tracker.register(type: "get_state")
        func response(_ id: String, _ command: String) throws -> PiAgentRPCEvent {
            try JSONDecoder().decode(PiAgentRPCEvent.self, from: JSONSerialization.data(withJSONObject: ["type": "response", "id": id, "command": command, "success": true]))
        }
        XCTAssertTrue(tracker.shouldDeliver(try response(second, "get_state")))
        XCTAssertFalse(tracker.shouldDeliver(try response(first, "get_state")))
        let mutation = tracker.register(type: "set_model")
        XCTAssertFalse(tracker.shouldDeliver(try response(second, "get_state")))
        let newerMutation = tracker.register(type: "cycle_model")
        XCTAssertTrue(tracker.shouldDeliver(try response(newerMutation, "cycle_model")))
        XCTAssertFalse(tracker.shouldDeliver(try response(mutation, "set_model")))
    }

    func testSlowPollingDoesNotStarveWhileNewerRequestIsPending() throws {
        let tracker = PiRPCResponseTracker()
        let first = tracker.register(type: "get_state")
        _ = tracker.register(type: "get_state")
        let data = try JSONSerialization.data(withJSONObject: ["type": "response", "id": first, "command": "get_state", "success": true])
        XCTAssertTrue(tracker.shouldDeliver(try JSONDecoder().decode(PiAgentRPCEvent.self, from: data)))
    }
}
