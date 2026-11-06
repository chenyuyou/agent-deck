import AppKit
import SwiftUI
import XCTest
@testable import agent_deck

final class PiAgentLaunchResolverTests: XCTestCase {
    @MainActor
    func testSessionAgentsAndMemorySettingsRenderOffscreen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let memory = AgentMemoryStore(rootURL: root)
        let viewModel = AppViewModel(memoryStore: memory)
        let store = viewModel.piAgentSessionStore
        let project = try PiTestSupport.makeProject()
        var session = store.createSession(kind: .project, title: "Settings preview", project: project, repository: nil)
        defer { store.deleteSessions([session.id], fallbackSelectionID: nil) }
        session.status = .running
        let record = try memory.createMemory(kind: .decision, status: .active, title: "Use native controls", summary: "Keep controls accessible", body: "Prefer native controls for navigation.", projectPath: project.path)
        try memory.setUserLocked(id: record.id, locked: true)
        let fixtures: [(String, AnyView)] = [
            ("agents", AnyView(PiAgentSessionModelsSheet(viewModel: viewModel, sessionID: session.id))),
            ("memory", AnyView(PiSessionMemorySettings(viewModel: viewModel, session: session, store: memory).padding(20)))
        ]
        for (name, fixture) in fixtures {
            let host = NSHostingView(rootView: fixture)
            host.frame = NSRect(x: 0, y: 0, width: 760, height: 640)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            XCTAssertTrue(host.fittingSize.height.isFinite)
            let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: image)
            let data = try XCTUnwrap(image.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: "/tmp/agent-deck-session-settings-\(name).png"))
            window.close()
        }
    }

    @MainActor
    func testSessionSettingsChangeOnlyTheTargetSession() throws {
        let memory = AgentMemoryStore(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let viewModel = AppViewModel(memoryStore: memory)
        let store = viewModel.piAgentSessionStore
        let project = try PiTestSupport.makeProject()
        let target = store.createSession(kind: .project, title: "Target", project: project, repository: nil)
        let other = store.createSession(kind: .project, title: "Other", project: project, repository: nil)
        defer { store.deleteSessions([target.id, other.id], fallbackSelectionID: nil) }
        store.updateSession(target.id) { $0.status = .running }
        viewModel.setAgentSelection(["explorer", "reviewer"], for: target.id)
        viewModel.setSubagentsEnabled(false, forSessionID: target.id)
        viewModel.setSessionMemoryPolicy(.init(enabled: true, automaticWrites: false, subagentsEnabled: false), sessionID: target.id)
        let changed = try XCTUnwrap(store.sessions.first { $0.id == target.id })
        XCTAssertEqual(changed.agentSelection, ["explorer", "reviewer"])
        XCTAssertFalse(changed.subagentsEnabled)
        XCTAssertEqual(changed.status, .running)
        XCTAssertEqual(changed.memoryPolicy?.automaticWrites, false)
        XCTAssertNil(store.sessions.first { $0.id == other.id }?.memoryPolicy)
        XCTAssertNil(store.sessions.first { $0.id == other.id }?.agentSelection)
    }

    @MainActor
    func testManualMemoryRevisionDeduplicationIsSessionScoped() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let memory = AgentMemoryStore(rootURL: root)
        let viewModel = AppViewModel(memoryStore: memory)
        let store = viewModel.piAgentSessionStore
        let project = try PiTestSupport.makeProject()
        let session = store.createSession(kind: .project, title: "Memory", project: project, repository: nil)
        defer { store.deleteSessions([session.id], fallbackSelectionID: nil) }
        let record = try memory.createMemory(kind: .context, status: .active, title: "Selected", summary: "", body: "Current revision", projectPath: project.path)
        store.updateSession(session.id) {
            $0.memoryPolicy = .init(enabled: true, automaticWrites: true, subagentsEnabled: true)
            $0.manuallyIncludedMemoryVersions = [record.id: record.updatedAt]
        }
        XCTAssertEqual(try viewModel.includeMemoriesInSession([record.id], sessionID: session.id), 0)
        store.updateSession(session.id) { $0.memoryPolicy?.enabled = false }
        XCTAssertThrowsError(try viewModel.includeMemoriesInSession([record.id], sessionID: session.id))
    }

    @MainActor
    func testRunningSessionModelEditorUpdatesSessionWithoutChangingActiveState() throws {
        let viewModel = AppViewModel()
        let store = viewModel.piAgentSessionStore
        let session = store.createSession(kind: .project, title: "Running editor", project: try PiTestSupport.makeProject(), repository: nil)
        defer { store.deleteSessions([session.id], fallbackSelectionID: nil) }
        store.updateSession(session.id) { $0.status = .running }
        let host = NSHostingView(rootView: PiAgentSessionModelsSheet(viewModel: viewModel, sessionID: session.id))
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 520)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 400)
        XCTAssertLessThan(host.fittingSize.height, 700)

        viewModel.setAgentLaunchOverride(.value("openai/chosen"), for: "explorer", field: \.model, sessionID: session.id)
        viewModel.setAgentLaunchOverride(.value("high"), for: "explorer", field: \.thinking, sessionID: session.id)
        let updated = try XCTUnwrap(store.sessions.first { $0.id == session.id })
        XCTAssertEqual(updated.status, .running)
        XCTAssertEqual(updated.agentLaunchOverrides?["explorer"]?.model, .value("openai/chosen"))
        XCTAssertEqual(updated.agentLaunchOverrides?["explorer"]?.thinking, .value("high"))
        host.layoutSubtreeIfNeeded()
        viewModel.setAgentLaunchOverride(nil, for: "explorer", field: \.model, sessionID: session.id)
        viewModel.setAgentLaunchOverride(nil, for: "explorer", field: \.thinking, sessionID: session.id)
        XCTAssertNil(store.sessions.first { $0.id == session.id }?.agentLaunchOverrides)
    }

    @MainActor
    func testSessionOverridesResolvePerAgentForDisplayAndLaunch() throws {
        let store = PiAgentSessionStore(fileURL: PiTestSupport.temporaryStateFile())
        var session = store.createSession(kind: .project, title: "Test", project: try PiTestSupport.makeProject(), repository: nil)
        session.status = .running
        session.agentLaunchOverrides = ["explorer": .init(model: .value("openai/default"), thinking: .value("low"))]
        let explorer = AppViewModel.applyingSessionLaunchOverrides(to: effectiveAgent(name: "explorer", id: "explorer"), session: session)
        let reviewer = effectiveAgent(name: "reviewer", id: "reviewer")
        session.agentLaunchOverrides = [
            "explorer": .init(model: .value("openai/chosen"), thinking: .value("high")),
            "reviewer": .init(model: .value("other/reviewer"), thinking: .value("medium"))
        ]

        let displayed = AppViewModel.applyingSessionLaunchOverrides(to: explorer, session: session)
        let other = AppViewModel.applyingSessionLaunchOverrides(to: reviewer, session: session)
        XCTAssertEqual(displayed.resolved.model, "openai/chosen")
        XCTAssertEqual(displayed.resolved.thinking, "high")
        XCTAssertEqual(other.resolved.model, "other/reviewer")
        XCTAssertEqual(other.resolved.thinking, "medium")
        XCTAssertEqual(PiSubagentLaunchPlanner.modelSelection(for: displayed, parentSession: session).modelArgument, "openai/chosen:high")
        XCTAssertEqual(explorer.resolved.model, "openai/default", "An already resolved launch keeps its model")

        session.agentLaunchOverrides = ["explorer": .init(model: .piDefault, thinking: .piDefault)]
        let piDefault = AppViewModel.applyingSessionLaunchOverrides(to: explorer, session: session)
        XCTAssertNil(piDefault.resolved.model)
        XCTAssertNil(piDefault.resolved.thinking)
        session.agentLaunchOverrides = nil
        let restored = AppViewModel.applyingSessionLaunchOverrides(to: explorer, session: session)
        XCTAssertEqual(restored.resolved.model, "openai/default")
        XCTAssertEqual(restored.resolved.thinking, "low")
    }

    @MainActor
    func testBuiltinOverrideSkillReferenceReplacementChangesOnlyMatchingSkills() throws {
        let root: [String: Any] = [
            "unrelated": ["kept": true],
            "subagents": [
                "agentOverrides": [
                    "explorer": ["skills": ["old-skill", "other-skill"]],
                    "coder": ["skills": "old-skill"]
                ]
            ]
        ]

        let updated = try XCTUnwrap(AppViewModel.replacingBuiltinOverrideSkillReferences(in: root, from: "old-skill", to: "new-skill"))
        let subagents = try XCTUnwrap(updated["subagents"] as? [String: Any])
        let overrides = try XCTUnwrap(subagents["agentOverrides"] as? [String: Any])
        let explorer = try XCTUnwrap(overrides["explorer"] as? [String: Any])
        let coder = try XCTUnwrap(overrides["coder"] as? [String: Any])
        XCTAssertEqual(explorer["skills"] as? [String], ["new-skill", "other-skill"])
        XCTAssertEqual(coder["skills"] as? String, "new-skill")
        XCTAssertEqual((updated["unrelated"] as? [String: Bool])?["kept"], true)
    }

    func testUnassignedCustomAgentsStayCatalogOnly() {
        let custom = agentRecord(name: "coder", kind: .global, path: "/tmp/coder.md")
        let snapshot = ScanSnapshot.empty
        let effective = PiAgentLaunchResolver.effectiveAgents(
            defaultAgentNames: [],
            projectAgentNames: [],
            snapshot: snapshot,
            catalog: [custom]
        )

        XCTAssertFalse(effective.contains { $0.name == "coder" })
    }

    func testAgentsByNameIndexesUniqueEffectiveAgents() throws {
        let explorer = effectiveAgent(name: "explorer", id: "project::explorer")
        let reviewer = effectiveAgent(name: "reviewer", id: "project::reviewer")

        let indexed = try PiAgentLaunchResolver.agentsByName([explorer, reviewer])

        XCTAssertEqual(indexed.keys.sorted(), ["explorer", "reviewer"])
        XCTAssertEqual(indexed["explorer"]?.id, explorer.id)
        XCTAssertEqual(indexed["reviewer"]?.id, reviewer.id)
    }

    func testAgentsByNameReportsDuplicateNamesInsteadOfTrappingOrChoosingOne() {
        let first = effectiveAgent(name: "reviewer", id: "global::reviewer")
        let second = effectiveAgent(name: "reviewer", id: "library::reviewer")

        XCTAssertThrowsError(try PiAgentLaunchResolver.agentsByName([first, second])) { error in
            XCTAssertEqual(
                error as? PiAgentLaunchResolver.DuplicateEffectiveAgentNamesError,
                PiAgentLaunchResolver.DuplicateEffectiveAgentNamesError(names: ["reviewer"])
            )
        }
    }

    func testDefaultAgentAssignmentMakesCatalogAgentEffective() {
        let custom = agentRecord(name: "coder", kind: .global, path: "/tmp/coder.md")
        let effective = PiAgentLaunchResolver.effectiveAgents(
            defaultAgentNames: ["coder"],
            projectAgentNames: [],
            snapshot: .empty,
            catalog: [custom]
        )

        let coder = effective.first { $0.name == "coder" }
        XCTAssertEqual(coder?.globalCustom?.filePath, "/tmp/coder.md")
        XCTAssertEqual(coder?.resolutionKind, .globalCustom)
    }

    func testProjectFallbackResolvesRequestedProjectAssignmentsWithoutLeakingDisplayedAgents() {
        let builtins = [
            agentRecord(name: "explorer", kind: .builtin, path: "/app/explorer.md"),
            agentRecord(name: "planner", kind: .builtin, path: "/app/planner.md"),
            agentRecord(name: "reviewer", kind: .builtin, path: "/app/reviewer.md")
        ]
        let appleDesigner = agentRecord(name: "apple-designer-expert", kind: .global, path: "/global/apple-designer-expert.md")
        let ponytail = agentRecord(name: "ponytail", kind: .global, path: "/global/ponytail.md")
        let displayedAgents = PiAgentLaunchResolver.effectiveAgents(
            defaultAgentNames: ["apple-designer-expert"],
            projectAgentNames: [],
            snapshot: .empty.replacing(projectRoot: "/projects/displayed", builtinAgents: builtins),
            catalog: [appleDesigner, ponytail]
        )
        let globalSnapshot = ScanSnapshot.empty.replacing(
            builtinAgents: builtins,
            globalAgents: [appleDesigner, ponytail],
            effectiveAgents: displayedAgents
        )

        let fallback = PiAgentLaunchResolver.projectFallbackSnapshot(
            from: globalSnapshot,
            projectRoot: "/projects/requested"
        )
        let resolved = PiAgentLaunchResolver.effectiveAgents(
            defaultAgentNames: [],
            projectAgentNames: ["ponytail"],
            snapshot: fallback,
            catalog: fallback.globalAgents + fallback.libraryAgents
        )

        XCTAssertEqual(fallback.projectRoot, "/projects/requested")
        XCTAssertTrue(fallback.effectiveAgents.isEmpty)
        XCTAssertEqual(Set(resolved.map(\.name)), ["explorer", "planner", "ponytail", "reviewer"])
        XCTAssertFalse(resolved.contains { $0.name == "apple-designer-expert" })
        XCTAssertTrue(resolved.allSatisfy { $0.projectRoot == "/projects/requested" })
    }

    func testProjectAssignmentUsesGlobalCatalogAgentByName() {
        let global = agentRecord(name: "reviewer", kind: .global, path: "/tmp/global-reviewer.md")
        let project = agentRecord(name: "reviewer", kind: .project, path: "/tmp/project/.pi/agents/reviewer.md")
        let snapshot = ScanSnapshot.empty.replacing(projectRoot: "/tmp/project")

        let effective = PiAgentLaunchResolver.effectiveAgents(
            defaultAgentNames: ["reviewer"],
            projectAgentNames: ["reviewer"],
            snapshot: snapshot,
            catalog: [global, project]
        )

        let reviewer = effective.first { $0.name == "reviewer" }
        XCTAssertEqual(reviewer?.globalCustom?.filePath, "/tmp/global-reviewer.md")
        XCTAssertNil(reviewer?.projectCustom)
        XCTAssertEqual(reviewer?.resolutionKind, .globalCustom)
    }

    func testProjectBuiltinSubagentConfigurationIsIgnored() {
        let projectRoot = "/tmp/project"
        let builtin = agentRecord(name: "explorer", kind: .builtin, path: "/app/bundled-agents/explorer.md")
        let globalSettings = settingsSummary(
            path: "/Users/test/.pi/agent/settings.json",
            overrides: [
                override(
                    name: "explorer",
                    path: "/Users/test/.pi/agent/settings.json",
                    values: [
                        "model": .string("openai-codex/gpt-5.4-mini"),
                        "thinking": .string("medium"),
                        "skills": .array([.string("agent-authoring")])
                    ]
                )
            ]
        )
        let projectSettings = settingsSummary(
            path: "\(projectRoot)/.pi/settings.json",
            overrides: [
                override(
                    name: "explorer",
                    path: "\(projectRoot)/.pi/settings.json",
                    values: [
                        "model": .string("project/ignored"),
                        "skills": .array([.string("project-only-skill")]),
                        "thinking": .bool(false)
                    ]
                )
            ],
            disableBuiltins: true
        )
        let snapshot = ScanSnapshot.empty.replacing(
            projectRoot: projectRoot,
            builtinAgents: [builtin],
            settings: [globalSettings, projectSettings]
        )

        let effective = PiAgentLaunchResolver.effectiveAgents(
            defaultAgentNames: [],
            projectAgentNames: [],
            snapshot: snapshot,
            catalog: []
        )

        let explorer = effective.first { $0.name == "explorer" }
        XCTAssertEqual(explorer?.resolved.model, "openai-codex/gpt-5.4-mini")
        XCTAssertEqual(explorer?.resolved.thinking, "medium")
        XCTAssertEqual(explorer?.resolved.skills, ["agent-authoring"])
        XCTAssertNil(explorer?.projectOverride)
        XCTAssertEqual(explorer?.resolutionKind, .builtinWithOverride)
    }

    private func effectiveAgent(name: String, id: String) -> EffectiveAgentRecord {
        let record = agentRecord(name: name, kind: .global, path: "/tmp/\(id).md")
        return EffectiveAgentRecord(
            id: id,
            name: name,
            projectRoot: "/tmp/project",
            builtin: nil,
            globalCustom: record,
            projectCustom: nil,
            userOverride: nil,
            projectOverride: nil,
            resolved: record.parsed,
            resolutionKind: .globalCustom
        )
    }

    private func agentRecord(name: String, kind: ResourceScopeKind, path: String) -> AgentRecord {
        var config = AgentConfig.empty
        config.name = name
        config.description = name
        config.systemPrompt = "You are \(name)."
        return AgentRecord(
            id: "\(kind.rawValue):\(path)",
            name: name,
            description: name,
            source: ScopeID(kind: kind, path: path),
            filePath: path,
            rawFrontmatter: [:],
            promptBody: config.systemPrompt,
            parsed: config
        )
    }

    private func settingsSummary(path: String, overrides: [BuiltinOverrideRecord], disableBuiltins: Bool? = nil) -> SettingsSummary {
        SettingsSummary(path: path, packages: [], prompts: [], disableBuiltins: disableBuiltins, agentOverrides: overrides)
    }

    private func override(name: String, path: String, values: [String: JSONValue]) -> BuiltinOverrideRecord {
        BuiltinOverrideRecord(
            agentName: name,
            scope: ScopeID(kind: .override, path: path),
            settingsPath: path,
            values: values
        )
    }
}

private extension ScanSnapshot {
    func replacing(
        projectRoot: String? = nil,
        builtinAgents: [AgentRecord]? = nil,
        globalAgents: [AgentRecord]? = nil,
        effectiveAgents: [EffectiveAgentRecord]? = nil,
        settings: [SettingsSummary]? = nil
    ) -> ScanSnapshot {
        ScanSnapshot(
            projectRoot: projectRoot ?? self.projectRoot,
            builtinAgents: builtinAgents ?? self.builtinAgents,
            globalAgents: globalAgents ?? self.globalAgents,
            projectAgents: projectAgents,
            legacyProjectAgents: legacyProjectAgents,
            effectiveAgents: effectiveAgents ?? self.effectiveAgents,
            libraryAgents: libraryAgents,
            skills: skills,
            librarySkills: librarySkills,
            promptTemplates: promptTemplates,
            libraryPromptTemplates: libraryPromptTemplates,
            settings: settings ?? self.settings,
            envKeys: envKeys,
            warnings: warnings
        )
    }
}
