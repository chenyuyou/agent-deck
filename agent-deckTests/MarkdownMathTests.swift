import AppKit
import XCTest
@testable import agent_deck

@MainActor
final class MarkdownMathTests: XCTestCase {
    private let font = NSFont.systemFont(ofSize: 16)

    func testMathJaxUsesDarkAppearanceTextColorOutsideDrawingContext() throws {
        let latex = "color-appearance-regression"
        MarkdownMath.mathJaxCompleted(latex: latex, display: true, svg: #"<svg xmlns="http://www.w3.org/2000/svg" width="2ex" height="2ex" viewBox="0 0 10 10"><rect width="10" height="10" fill="currentColor"/></svg>"#)
        var prepared: MarkdownMath.Prepared?
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            prepared = MarkdownMath.prepare("$$\(latex)$$", font: font, color: .labelColor)
        }
        let image = try XCTUnwrap(prepared?.formulas.first?.image)
        var rect = NSRect(origin: .zero, size: image.size)
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil)))
        let pixel = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(pixel.redComponent, 0.7, "Formula foreground must be visible on the app's dark background")
    }

    func testRealMathJaxFormulaIsLightOnDarkBackground() async throws {
        let latex = #"\frac{2026}{x^2}"#
        let source = "$$\(latex)$$"
        _ = MarkdownMath.prepare(source, font: font, color: .labelColor)
        let deadline = Date().addingTimeInterval(8)
        while MarkdownMath.mathJaxTestState(latex, display: true) == "pending" && Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(MarkdownMath.mathJaxTestState(latex, display: true), "rendered")
        var prepared: MarkdownMath.Prepared?
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            prepared = MarkdownMath.prepare(source, font: font, color: .labelColor)
        }
        let image = try XCTUnwrap(prepared?.formulas.first?.image)
        var rect = NSRect(origin: .zero, size: image.size)
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil)))
        var brightness: [CGFloat] = []
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.5 {
                    brightness.append(color.redComponent)
                }
            }
        }
        XCTAssertFalse(brightness.isEmpty)
        XCTAssertGreaterThan(brightness.reduce(0, +) / CGFloat(max(brightness.count, 1)), 0.7)
    }

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

    func testMathJaxUpdateKeepsUnrelatedTextViews() async throws {
        let latex = #"\bbox[red]{refreshOnlyThisFormula}"#
        let source = "First paragraph.\n\n$$\(latex)$$\n\nLast paragraph."
        let container = NativeMarkdownTextContainer(frame: .zero)
        let applier = MarkdownSourceApplier()
        defer { applier.cancel(); container.dismantle() }
        applier.apply(source: source, to: container)
        func textViews(_ view: NSView) -> [NSTextView] {
            (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(textViews)
        }
        let before = textViews(container)
        XCTAssertEqual(before.count, 3)
        let updated = expectation(forNotification: MarkdownMath.mathJaxUpdated, object: nil) {
            ($0.object as? [String])?.contains(latex) == true
        }
        MarkdownMath.mathJaxCompleted(latex: latex, display: true, svg: #"<svg xmlns="http://www.w3.org/2000/svg" width="2ex" height="2ex" viewBox="0 0 10 10"><rect width="10" height="10" fill="currentColor"/></svg>"#)
        await fulfillment(of: [updated], timeout: 3)
        let after = textViews(container)
        XCTAssertEqual(after.count, 3)
        XCTAssertTrue(before[0] === after[0])
        XCTAssertTrue(before[2] === after[2])
        let storage = try XCTUnwrap(after[1].textStorage)
        XCTAssertNotNil(storage.attribute(.attachment, at: 0, effectiveRange: nil))
    }

    func testMathJaxUpdateKeepsTableCellsAndOtherFormulas() async throws {
        let latex = #"\bbox[red]{tableRefreshRegression}"#
        let source = "| Formula | Other |\n| --- | --- |\n| $$\(latex)$$ | $x^2$ |"
        let container = NativeMarkdownTextContainer(frame: .zero)
        let applier = MarkdownSourceApplier()
        defer { applier.cancel(); container.dismantle() }
        applier.apply(source: source, to: container)
        func textViews(_ view: NSView) -> [NSTextView] {
            (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(textViews)
        }
        let before = textViews(container)
        XCTAssertEqual(before.count, 4)
        let updated = expectation(forNotification: MarkdownMath.mathJaxUpdated, object: nil) {
            ($0.object as? [String])?.contains(latex) == true
        }
        MarkdownMath.mathJaxCompleted(latex: latex, display: true, svg: #"<svg xmlns="http://www.w3.org/2000/svg" width="2ex" height="2ex" viewBox="0 0 10 10"><rect width="10" height="10" fill="currentColor"/></svg>"#)
        await fulfillment(of: [updated], timeout: 3)
        let after = textViews(container)
        XCTAssertEqual(after.count, before.count)
        for (old, new) in zip(before, after) { XCTAssertTrue(old === new) }
        let storage = try XCTUnwrap(after[2].textStorage)
        XCTAssertNotNil(storage.attribute(.attachment, at: 0, effectiveRange: nil))
    }

    func testStreamingAppendDoesNotRescanUnchangedBlocks() {
        let container = NativeMarkdownTextContainer(frame: .zero)
        let applier = MarkdownSourceApplier()
        defer { applier.cancel(); container.dismantle() }
        let initial = (0..<30).map { "Paragraph \($0): $x_\($0)$" }.joined(separator: "\n\n")
        applier.apply(source: initial, to: container)
        let count = NativeMarkdownTextContainer.formulaIndexScanCount
        applier.apply(source: initial + "\n\nNew paragraph $y$", to: container)
        XCTAssertEqual(NativeMarkdownTextContainer.formulaIndexScanCount - count, 1)
    }

    func testFormulaCompletionInvalidatesTranscriptCache() async throws {
        let latex = #"\bbox[blue]{cachedTranscriptRegression}"#
        let source = "$$\(latex)$$"
        _ = TranscriptAttributedStringBuilder.attributedString(for: source)
        let updated = expectation(forNotification: MarkdownMath.mathJaxUpdated, object: nil) {
            ($0.object as? [String])?.contains(latex) == true
        }
        MarkdownMath.mathJaxCompleted(latex: latex, display: true, svg: #"<svg xmlns="http://www.w3.org/2000/svg" width="2ex" height="2ex" viewBox="0 0 10 10"><rect width="10" height="10" fill="currentColor"/></svg>"#)
        await fulfillment(of: [updated], timeout: 3)
        let rendered = TranscriptAttributedStringBuilder.attributedString(for: source)
        XCTAssertNotEqual((rendered.string as NSString).range(of: "\u{FFFC}").location, NSNotFound)
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
