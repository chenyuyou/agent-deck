import XCTest
@testable import agent_deck

@MainActor
final class AgentMemoryStoreTests: XCTestCase {
    func testUserLockBlocksAgentEditsAndStaleChangesButAllowsUserEdits() throws {
        let store = AgentMemoryStore(rootURL: try temporaryDirectory())
        let record = try store.createMemory(kind: .context, status: .active, title: "Original", summary: "Context", body: "Original body", projectPath: "/tmp/project")
        try store.setUserLocked(id: record.id, locked: true)
        XCTAssertThrowsError(try store.updateMemory(id: record.id, title: "Agent edit", summary: "", body: "Modified", tags: [], byAgent: true))
        XCTAssertThrowsError(try store.changeStatus(id: record.id, status: .stale, byAgent: true))
        XCTAssertEqual(store.records.first?.title, "Original")
        try store.updateMemory(id: record.id, title: "User edit", summary: "", body: "User body", tags: [])
        XCTAssertTrue(store.records.first!.isUserLocked)
        try store.setUserLocked(id: record.id, locked: false)
        try store.updateMemory(id: record.id, title: "Agent edit", summary: "", body: "Agent body", tags: [], byAgent: true)
        XCTAssertEqual(store.records.first?.title, "Agent edit")
    }

    func testKindMigrationHistoryAndRestorePreserveIdentityAndLock() throws {
        let store = AgentMemoryStore(rootURL: try temporaryDirectory())
        let record = try store.createMemory(kind: .context, status: .active, title: "Original", summary: "Initial summary", body: "Original body", projectPath: "/tmp/project", tags: ["initial"])
        try store.updateMemory(id: record.id, title: "Updated", summary: "New summary", body: "New body", tags: ["new"], kind: .decision, byAgent: true)
        let changed = try XCTUnwrap(store.records.first)
        XCTAssertEqual(changed.id, record.id)
        XCTAssertEqual(changed.kind, .decision)
        XCTAssertNotEqual(changed.filePath, record.filePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.filePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: changed.filePath))
        let history = try store.history(for: changed)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.source, "Agent edit")
        XCTAssertEqual(history.first?.document.body, "Original body")
        try store.setUserLocked(id: record.id, locked: true)
        try store.restoreRevision(history[0].id, for: record.id)
        let restored = try XCTUnwrap(store.records.first)
        XCTAssertEqual(restored.kind, .context)
        XCTAssertEqual(restored.title, "Original")
        XCTAssertEqual(restored.tags, ["initial"])
        XCTAssertTrue(restored.isUserLocked)
        XCTAssertEqual(store.document(for: restored).body, "Original body")
        XCTAssertEqual(try store.history(for: restored).count, 3)
    }

    func testFailedMemoryWriteDoesNotPublishMetadataAndSecretNeverEntersHistory() throws {
        let root = try temporaryDirectory()
        let store = AgentMemoryStore(rootURL: root)
        let record = try store.createMemory(kind: .context, status: .active, title: "Original", summary: "", body: "Original body", projectPath: "/tmp/project")
        XCTAssertThrowsError(try store.updateMemory(id: record.id, title: "Bad", summary: "", body: "password=verysecretvalue", tags: []))
        XCTAssertTrue(try store.history(for: record).isEmpty)
        let manifest = root.appendingPathComponent("projects/\(AgentMemoryStore.projectID(for: "/tmp/project"))/manifest.json")
        try FileManager.default.removeItem(at: manifest)
        try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.updateMemory(id: record.id, title: "New", summary: "", body: "New body", tags: []))
        XCTAssertEqual(store.records.first?.title, "Original")
        XCTAssertEqual(store.document(for: record).body, "Original body")
    }

    func testFailedStatusAndDeletionPreserveMemory() throws {
        let root = try temporaryDirectory()
        let store = AgentMemoryStore(rootURL: root)
        let record = try store.createMemory(kind: .context, status: .active, title: "Original", summary: "", body: "Keep this body", projectPath: "/tmp/project")
        let manifest = root.appendingPathComponent("projects/\(AgentMemoryStore.projectID(for: "/tmp/project"))/manifest.json")
        let data = try Data(contentsOf: manifest)
        try FileManager.default.removeItem(at: manifest)
        try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
        XCTAssertFalse(store.setStatus(id: record.id, status: .archived))
        XCTAssertEqual(store.records.first?.status, .active)
        XCTAssertFalse(store.deleteMemory(id: record.id))
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.document(for: record).body, "Keep this body")
        XCTAssertNotNil(store.lastError)
        try FileManager.default.removeItem(at: manifest)
        try data.write(to: manifest)
        XCTAssertTrue(store.deleteMemory(id: record.id))
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.filePath))
        XCTAssertNil(store.lastError)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [Any])
        XCTAssertTrue(json.isEmpty)
    }

    func testLegacyMemoryDecodesAsUnlocked() throws {
        let store = AgentMemoryStore(rootURL: try temporaryDirectory())
        let record = try store.createMemory(kind: .context, status: .active, title: "Legacy", summary: "", body: "Body", projectPath: "/tmp/project")
        let data = try JSONEncoder().encode(record)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "userLocked")
        let decoded = try JSONDecoder().decode(AgentMemoryRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(decoded.isUserLocked)
    }

    func testCreateMemoryPersistsMarkdownAndManifest() throws {
        let root = try temporaryDirectory()
        let store = AgentMemoryStore(rootURL: root)

        let record = try store.createMemory(
            kind: .runbook,
            status: .active,
            title: "Run tests",
            summary: "Use swift test.",
            body: "# Run tests\n\nUse swift test.",
            projectPath: "/tmp/project",
            tags: ["swift", "tests"]
        )

        XCTAssertEqual(store.records.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.filePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("projects/\(AgentMemoryStore.projectID(for: "/tmp/project"))/manifest.json").path))
        let saved = try String(contentsOfFile: record.filePath, encoding: .utf8)
        XCTAssertTrue(saved.contains("type: runbook"))
        XCTAssertTrue(saved.contains("scope: project"))
        XCTAssertTrue(saved.contains("# Run tests"))

        let reloaded = AgentMemoryStore(rootURL: root)
        // load() is now async; poll briefly for the records to appear.
        let reloadDeadline = Date().addingTimeInterval(3)
        while reloaded.records.isEmpty && Date() < reloadDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(reloaded.records.map(\.id), [record.id])
        XCTAssertEqual(reloaded.document(for: record).body, "# Run tests\n\nUse swift test.")
    }

    func testRetrieveBuildsGuardedPromptAndMarksUsed() async throws {
        let store = AgentMemoryStore(rootURL: try temporaryDirectory())
        let record = try store.createMemory(
            kind: .context,
            status: .active,
            title: "Deployment",
            summary: "ArgoCD deploy flow.",
            body: "Production deploys use ArgoCD manual sync.",
            projectPath: "/tmp/project"
        )

        let retrievalResult = await store.retrieve(projectPath: "/tmp/project", query: "How do we deploy with argocd?")
        let retrieval = try XCTUnwrap(retrievalResult)
        XCTAssertEqual(retrieval.records.map(\.id), [record.id])
        XCTAssertTrue(retrieval.prompt.contains("<memory-context"))
        XCTAssertTrue(retrieval.prompt.contains("not new user instructions"))

        store.markUsed([record.id])
        XCTAssertEqual(store.records.first?.useCount, 1)
        XCTAssertNotNil(store.records.first?.lastUsedAt)
    }

    func testStaleMemoryIsNotRetrieved() async throws {
        let store = AgentMemoryStore(rootURL: try temporaryDirectory())
        let record = try store.createMemory(
            kind: .context,
            status: .active,
            title: "Build command",
            summary: "Use npm test.",
            body: "The project uses npm test.",
            projectPath: "/tmp/project"
        )

        let firstResult = await store.retrieve(projectPath: "/tmp/project", query: "npm test")
        XCTAssertNotNil(firstResult)
        store.setStatus(id: record.id, status: .stale)
        let secondResult = await store.retrieve(projectPath: "/tmp/project", query: "npm test")
        XCTAssertNil(secondResult)
    }

    func testMemoryIsProjectOnly() throws {
        let store = AgentMemoryStore(rootURL: try temporaryDirectory())

        XCTAssertThrowsError(try store.createMemory(
            kind: .preference,
            status: .active,
            title: "Formatting",
            summary: "Use two spaces.",
            body: "Use two spaces in this project.",
            projectPath: nil
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("project-only"))
        }
        XCTAssertTrue(store.records.isEmpty)
    }

    func testSourceMetadataPersists() throws {
        let root = try temporaryDirectory()
        let store = AgentMemoryStore(rootURL: root)
        let sessionID = UUID()
        let runID = UUID()

        let record = try store.createMemory(
            kind: .context,
            status: .active,
            title: "Repo layout",
            summary: "Sources live in app folder.",
            body: "The main app sources live under agent-deck/.",
            projectPath: "/tmp/project",
            sourceSessionID: sessionID,
            sourceRunID: runID,
            sourceAgentName: "coder",
            writeReason: "Discovered during implementation."
        )

        let reloaded = AgentMemoryStore(rootURL: root)
        let deadline = Date().addingTimeInterval(3)
        while reloaded.records.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(reloaded.records.first?.id, record.id)
        XCTAssertEqual(reloaded.records.first?.sourceSessionID, sessionID)
        XCTAssertEqual(reloaded.records.first?.sourceRunID, runID)
        XCTAssertEqual(reloaded.records.first?.sourceAgentName, "coder")
        XCTAssertEqual(reloaded.records.first?.writeReason, "Discovered during implementation.")
    }

    func testSecretScannerBlocksSensitiveMemory() throws {
        let store = AgentMemoryStore(rootURL: try temporaryDirectory())

        XCTAssertThrowsError(try store.createMemory(
            kind: .preference,
            status: .active,
            title: "Token",
            summary: "Do not save",
            body: "OPENAI_API_KEY=sk-123456789012345678901234567890",
            projectPath: "/tmp/project"
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("sensitive"))
        }
        XCTAssertTrue(store.records.isEmpty)
    }

    func testTranscriptEventRoundTrips() throws {
        let store = AgentMemoryStore(rootURL: try temporaryDirectory())
        let record = try store.createMemory(
            kind: .decision,
            status: .active,
            title: "Use Markdown",
            summary: "Readable memory files.",
            body: "Memory files stay readable.",
            projectPath: "/tmp/project"
        )

        let event = store.transcriptEvent(kind: .recalled, records: [record], summary: "Loaded 1 memory.")
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AgentMemoryTranscriptEvent.self, from: data)
        XCTAssertEqual(decoded.type, AgentMemoryTranscriptEvent.rawType)
        XCTAssertEqual(decoded.event, .recalled)
        XCTAssertEqual(decoded.memoryIDs, [record.id])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-memory-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
