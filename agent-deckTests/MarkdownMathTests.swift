import AppKit
import XCTest
@testable import agent_deck

@MainActor
final class MarkdownMathTests: XCTestCase {
    private let font = NSFont.systemFont(ofSize: 16)

    func testChineseMultilineExampleRendersAndPreservesSource() throws {
        let source = "[\n\\text{客观收益}\n\\rightarrow\n\\text{比较或适应度}\n\\rightarrow\n\\text{合作边界}.\n]"
        let result = MarkdownMath.prepare(source, font: font, color: .labelColor)
        XCTAssertEqual(result.formulas.count, 1)
        XCTAssertEqual(result.formulas.first?.original, source)
        XCTAssertGreaterThan(try XCTUnwrap(result.formulas.first?.image.size.width), 10)
        let attributed = NSMutableAttributedString(string: result.text)
        MarkdownMath.apply(result, to: attributed)
        XCTAssertNotNil(attributed.attribute(.attachment, at: 0, effectiveRange: nil))
        XCTAssertEqual(attributed.attribute(MarkdownMath.sourceAttribute, at: 0, effectiveRange: nil) as? String, source)
    }

    func testBoxedChineseFormulaWithBlankLinesRenders() throws {
        let source = "[\n\n\\boxed{\n\n\\text{本文的评价—聚合接口是否产生了已有模型没有的可证明、可检验结果？}\n\n}\n\n]"
        let prepared = MarkdownMath.prepare(source, font: font, color: .labelColor)
        XCTAssertEqual(prepared.formulas.count, 1)
        let formula = try XCTUnwrap(prepared.formulas.first)
        let preview = XCTAttachment(image: formula.image)
        preview.name = "Boxed Chinese formula"
        preview.lifetime = .keepAlways
        add(preview)
        XCTAssertEqual(formula.original, source)
        XCTAssertLessThanOrEqual(formula.image.size.width, 450)
        XCTAssertGreaterThan(formula.image.size.height, 35)
        let attributed = NSMutableAttributedString(string: prepared.text)
        MarkdownMath.apply(prepared, to: attributed)
        let attachment = try XCTUnwrap(attributed.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
        let narrowBounds = attachment.attachmentBounds(for: nil, proposedLineFragment: NSRect(x: 0, y: 0, width: 200, height: 100), glyphPosition: .zero, characterIndex: 0)
        XCTAssertLessThanOrEqual(narrowBounds.width, 200)
        let container = NativeMarkdownTextContainer(frame: .zero)
        let applier = MarkdownSourceApplier()
        defer { applier.cancel(); container.dismantle() }
        applier.apply(source: source, to: container)
        func findText(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.lazy.compactMap { findText($0) }.first
        }
        let storage = try XCTUnwrap(findText(container)?.textStorage)
        XCTAssertEqual(storage.attribute(MarkdownMath.sourceAttribute, at: 0, effectiveRange: nil) as? String, source)
        XCTAssertEqual((storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment, .center)
    }

    func testBoxedMathematicsAndMalformedBox() {
        let valid = MarkdownMath.prepare(#"$$\boxed{\frac{a}{b} + x^2}$$"#, font: font, color: .labelColor)
        XCTAssertEqual(valid.formulas.count, 1)
        let invalid = #"$$\boxed{\unknowncommand{x}}$$"#
        let unsupported = MarkdownMath.prepare(invalid, font: font, color: .labelColor)
        XCTAssertTrue(unsupported.formulas.isEmpty)
        XCTAssertEqual(unsupported.text, invalid)
    }

    func testInlineAndDisplayDelimiters() {
        let source = #"Inline $x^2$ and \(\frac{1}{2}\), display $$\sqrt{x}$$ and \[x+y\]."#
        let result = MarkdownMath.prepare(source, font: font, color: .labelColor)
        XCTAssertEqual(result.formulas.count, 4)
    }

    func testCodeCurrencyAndIncompleteFormulaStayUnchanged() {
        for source in [#"Use `$x^2$` as code"#, "Cost $5 and $10", #"unfinished \(x^2"#, "[\nordinary text\n]"] {
            let result = MarkdownMath.prepare(source, font: font, color: .labelColor)
            XCTAssertTrue(result.formulas.isEmpty, source)
            XCTAssertEqual(result.text, source)
        }
    }

    func testUnsupportedCommandRemainsReadable() {
        let source = #"$\definitelyNotARealCommand{x}$"#
        let result = MarkdownMath.prepare(source, font: font, color: .labelColor)
        XCTAssertTrue(result.formulas.isEmpty)
        XCTAssertEqual(result.text, source)
    }

    func testEnglishAndInlineFormulaRemainTogether() {
        let source = #"The solution is $x^2$ and the result is positive."#
        let rendered = TranscriptAttributedStringBuilder.attributedString(for: source)
        XCTAssertTrue(rendered.string.contains("The solution is"))
        XCTAssertTrue(rendered.string.contains("and the result is positive."))
        XCTAssertEqual((rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment, .natural)
        let range = (rendered.string as NSString).range(of: "\u{FFFC}")
        XCTAssertNotEqual(range.location, NSNotFound)
        if range.location != NSNotFound {
            XCTAssertEqual(rendered.attribute(MarkdownMath.sourceAttribute, at: range.location, effectiveRange: nil) as? String, "$x^2$")
        }
    }

    func testDisplayFormulaBetweenEnglishParagraphsIsCentered() {
        let source = "Before the formula.\n\\[\nx^2 + y^2 = z^2\n\\]\nAfter the formula."
        let rendered = TranscriptAttributedStringBuilder.attributedString(for: source)
        XCTAssertTrue(rendered.string.contains("Before the formula."))
        XCTAssertTrue(rendered.string.contains("After the formula."))
        let range = (rendered.string as NSString).range(of: "\u{FFFC}")
        XCTAssertNotEqual(range.location, NSNotFound)
        if range.location != NSNotFound {
            XCTAssertEqual((rendered.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)?.alignment, .center)
        }
    }

    func testNativeTranscriptRendersChineseExample() throws {
        let source = "[\n\\text{客观收益}\n\\rightarrow\n\\text{比较或适应度}\n\\rightarrow\n\\text{合作边界}.\n]"
        let container = NativeMarkdownTextContainer(frame: .zero)
        let applier = MarkdownSourceApplier()
        defer { applier.cancel(); container.dismantle() }
        applier.apply(source: source, to: container)
        func findText(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.lazy.compactMap { findText($0) }.first
        }
        let text = try XCTUnwrap(findText(container))
        let storage = try XCTUnwrap(text.textStorage)
        XCTAssertNotNil(storage.attribute(.attachment, at: 0, effectiveRange: nil))
        XCTAssertEqual((storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment, .center)
        XCTAssertEqual(storage.attribute(MarkdownMath.sourceAttribute, at: 0, effectiveRange: nil) as? String, source)
    }

    func testMathJaxRendersAdditionalCommandsInLiveTranscript() async throws {
        let source = #"$$\bbox[red]{x}$$"#
        let container = NativeMarkdownTextContainer(frame: .zero)
        let applier = MarkdownSourceApplier()
        defer { applier.cancel(); container.dismantle() }
        applier.apply(source: source, to: container)
        func findText(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.lazy.compactMap { findText($0) }.first
        }
        let deadline = Date().addingTimeInterval(8)
        var found = false
        while Date() < deadline {
            if let storage = findText(container)?.textStorage, storage.length > 0,
               storage.attribute(MarkdownMath.sourceAttribute, at: 0, effectiveRange: nil) as? String == source {
                if let attachment = storage.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment,
                   let image = attachment.image {
                    let preview = XCTAttachment(image: image)
                    preview.name = "MathJax background conversion"
                    preview.lifetime = .keepAlways
                    add(preview)
                }
                found = true
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertTrue(found, "MathJax should render bbox after background conversion")
    }

    func testOldMathJaxResultDoesNotReplaceNewerMessage() async throws {
        let container = NativeMarkdownTextContainer(frame: .zero)
        let applier = MarkdownSourceApplier()
        defer { applier.cancel(); container.dismantle() }
        applier.apply(source: #"$$\bbox[blue]{stale}$$"#, to: container)
        applier.apply(source: "Newer message", to: container)
        try await Task.sleep(for: .milliseconds(500))
        func findText(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.lazy.compactMap { findText($0) }.first
        }
        XCTAssertEqual(findText(container)?.string, "Newer message")
    }

    func testTranscriptBuilderIncludesFormulaAttachment() {
        let source = #"答案为$x^2$。"#
        let rendered = TranscriptAttributedStringBuilder.attributedString(for: source)
        var found = false
        rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            found = found || value != nil
        }
        XCTAssertTrue(found)
    }
}
