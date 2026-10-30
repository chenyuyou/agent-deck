import XCTest
@testable import agent_deck

@MainActor
final class ChineseTextSupportTests: XCTestCase {
    func testChineseRecallTermsMatchPhrasesWithoutSpaces() {
        let query = AgentMemoryStore.recallTerms(in: "怎么配置中文输入法")
        let title = AgentMemoryStore.recallTerms(in: "中文输入法配置")
        XCTAssertGreaterThanOrEqual(query.intersection(title).count, 2)
        XCTAssertEqual(AgentMemoryStore.recallTerms(in: "中文"), ["中文"])
        XCTAssertTrue(AgentMemoryStore.containsCJKBigram("中文"))
        XCTAssertFalse(AgentMemoryStore.containsCJKBigram("a中b文"))
        XCTAssertTrue(AgentMemoryStore.recallTerms(in: "Pi 输入法 swift").contains("swift"))
    }

    func testChinesePromptEstimateDoesNotUseEnglishOnlyRatio() {
        XCTAssertEqual(PromptTokenEstimate.estimate(""), 0)
        XCTAssertEqual(PromptTokenEstimate.estimate("abcdefgh"), 2)
        XCTAssertEqual(PromptTokenEstimate.estimate("中文输入"), 4)
        XCTAssertEqual(PromptTokenEstimate.estimate("abcd中文"), 3)
    }
}
