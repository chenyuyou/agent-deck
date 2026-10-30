import XCTest
@testable import agent_deck

@MainActor
final class CommandRunnerOutputTests: XCTestCase {
    func testConcurrentShortCommandsPreserveOutput() async throws {
        let results = try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for index in 0..<100 {
                group.addTask {
                    let result = try await CommandRunner().run("/usr/bin/printf", arguments: ["value-\(index)"], currentDirectoryURL: nil, timeout: 10, environment: nil)
                    return (index, await result.stdout)
                }
            }
            var values: [(Int, String)] = []
            for try await value in group { values.append(value) }
            return values
        }
        XCTAssertEqual(results.count, 100)
        for (index, output) in results { XCTAssertEqual(output, "value-\(index)") }
    }

    func testLargeStandardOutputAndErrorAreBothDrained() async throws {
        let command = #"head -c 200000 /dev/zero | tr '\0' a; head -c 100000 /dev/zero | tr '\0' b >&2"#
        let result = try await CommandRunner().run("/bin/sh", arguments: ["-c", command], currentDirectoryURL: nil, timeout: 10, environment: nil)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, String(repeating: "a", count: 200_000))
        XCTAssertEqual(result.stderr, String(repeating: "b", count: 100_000))
    }
}
