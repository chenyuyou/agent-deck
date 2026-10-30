import AppKit
import XCTest
@testable import agent_deck

@MainActor
final class LatexCompatibilityTests: XCTestCase {
    private func textViews(_ view: NSView) -> [NSTextView] {
        (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(textViews)
    }

    private func hasFormula(_ source: String, in container: NativeMarkdownTextContainer) -> Bool {
        textViews(container).contains { view in
            guard let storage = view.textStorage, storage.length > 0 else { return false }
            var matched = false
            storage.enumerateAttribute(MarkdownMath.sourceAttribute, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
                if value as? String == source { matched = true }
            }
            return matched
        }
    }

    func testCommonFormulaCorpusThroughLiveTranscript() async throws {
        let cases: [(String, String)] = [
            ("中文相邻行内", #"答案为$x^2$，其中 x 为变量。"#),
            ("英文行内", #"Given \(E=mc^2\), energy is conserved."#),
            ("分数和根号", #"$$x=\frac{-b\pm\sqrt{b^2-4ac}}{2a}$$"#),
            ("求和积分极限", #"\[\int_0^1 x^2\,dx=\lim_{n\to\infty}\sum_{i=1}^n \frac{i^2}{n^3}\]"#),
            ("希腊字母箭头", #"$\alpha+\beta\rightarrow\gamma$"#),
            ("偏导和梯度", #"$\nabla f=\frac{\partial f}{\partial x}$"#),
            ("上下标", #"$a_{i,j}^{(n)}$"#),
            ("括号定界", #"$\left(\frac{a}{b}\right)$"#),
            ("组合数", #"$\binom{n}{k}$"#),
            ("上划线与向量", #"$\overline{x}+\hat{y}+\vec{v}$"#),
            ("分段函数", #"$$f(x)=\begin{cases}x^2 & x>0 \\ 0 & x\le 0\end{cases}$$"#),
            ("矩阵", #"$$\begin{pmatrix}a&b\\c&d\end{pmatrix}$$"#),
            ("方括号矩阵", #"$$\begin{bmatrix}1&2\\3&4\end{bmatrix}$$"#),
            ("对齐环境", #"$$\begin{aligned}a&=b+c\\d&=e+f\end{aligned}$$"#),
            ("集合与逻辑", #"$\forall x\in\mathbb{R},\; x^2\ge 0$"#),
            ("数学文字", #"$\text{收益}=\operatorname{max}(x,y)$"#),
            ("嵌套边框", #"$$1+\boxed{\frac{a}{b}}=c$$"#),
            ("MathJax 边框扩展", #"$$\bbox[red]{x}$$"#),
            ("化学式", #"$\ce{H2O + CO2 -> H2CO3}$"#),
            ("无界定符 equation", #"\begin{equation}x^2+y^2=z^2\end{equation}"#),
            ("无界定符 align", "\\begin{align}\na &= b + c \\\\\nd &= e + f\n\\end{align}")
        ]
        for (name, source) in cases {
            let container = NativeMarkdownTextContainer(frame: .zero)
            let applier = MarkdownSourceApplier()
            applier.apply(source: source, to: container)
            let deadline = Date().addingTimeInterval(5)
            var rendered = false
            while Date() < deadline {
                let views = textViews(container)
                rendered = views.contains { view in
                    guard let storage = view.textStorage, storage.length > 0 else { return false }
                    var found = false
                    storage.enumerateAttribute(MarkdownMath.sourceAttribute, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
                        if value != nil { found = true }
                    }
                    return found
                }
                if rendered { break }
                try await Task.sleep(for: .milliseconds(25))
            }
            XCTAssertTrue(rendered, "\(name): \(source)")
            applier.cancel()
            container.dismantle()
        }
    }

    func testLatexInsideCodeRemainsLiteral() {
        let source = "```latex\n\\begin{equation}\nx^2\n\\end{equation}\n```"
        let container = NativeMarkdownTextContainer(frame: .zero)
        let applier = MarkdownSourceApplier()
        defer { applier.cancel(); container.dismantle() }
        applier.apply(source: source, to: container)
        let views = textViews(container)
        XCTAssertTrue(views.contains { $0.string.contains(#"\begin{equation}"#) })
        XCTAssertFalse(views.contains { view in
            guard let storage = view.textStorage, storage.length > 0 else { return false }
            var found = false
            storage.enumerateAttribute(MarkdownMath.sourceAttribute, in: NSRange(location: 0, length: storage.length)) { value, _, _ in found = found || value != nil }
            return found
        })
    }

    func testMathJaxActuallyParsesRepresentativeFormulae() async throws {
        let samples: [(String, String)] = [
            ("分式与根号", #"\frac{-b\pm\sqrt{b^2-4ac}}{2a}"#),
            ("积分求和", #"\int_0^1 x^2\,dx=\lim_{n\to\infty}\sum_{i=1}^n \frac{i^2}{n^3}"#),
            ("分段", #"f(x)=\begin{cases}x^2 & x>0 \\ 0 & x\le 0\end{cases}"#),
            ("矩阵", #"\begin{pmatrix}a&b\\c&d\end{pmatrix}"#),
            ("对齐", #"\begin{aligned}a&=b+c\\d&=e+f\end{aligned}"#),
            ("嵌套边框", #"1+\boxed{\frac{a}{b}}=c"#),
            ("扩展边框", #"\bbox[red]{x}"#),
            ("化学", #"\ce{H2O + CO2 -> H2CO3}"#),
            ("中文文字", #"\text{客观收益}\rightarrow\text{合作边界}"#),
            ("公式环境", #"\begin{equation}x^2+y^2=z^2\end{equation}"#),
            ("数字后的括号", #"\sum_{i=1}^n"#),
            ("数字后命令", #"\begin{cases}1&x>0\\0&x\le 0\end{cases}"#),
            ("小数与科学计数", #"1.25+0.5+3\times 10^{-2}"#),
            ("偏导和梯度", #"\nabla f=\frac{\partial f}{\partial x}"#),
            ("组合数", #"\binom{n}{k}"#),
            ("上划线与向量", #"\overline{x}+\hat{y}+\vec{v}"#),
            ("方括号矩阵", #"\begin{bmatrix}1&2\\3&4\end{bmatrix}"#)
        ]
        for (_, latex) in samples {
            _ = MarkdownMath.prepare("$$\(latex)$$", font: NSFont.systemFont(ofSize: 16), color: .labelColor)
        }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline && samples.contains(where: { MarkdownMath.mathJaxTestState($0.1, display: true) == "pending" }) {
            try await Task.sleep(for: .milliseconds(25))
        }
        for (name, latex) in samples {
            XCTAssertEqual(MarkdownMath.mathJaxTestState(latex, display: true), "rendered", name)
        }
    }

    func testPlainCurrencyAndEscapedDollarRemainLiteral() {
        let source = #"Prices are $5 and $10, and \$x$ is literal."#
        let result = MarkdownMath.prepare(source, font: NSFont.systemFont(ofSize: 16), color: .labelColor)
        XCTAssertTrue(result.formulas.isEmpty)
        XCTAssertEqual(result.text, source)
    }

    func testStreamingIncompleteFormulaBecomesRenderedWhenClosed() async throws {
        let container = NativeMarkdownTextContainer(frame: .zero)
        let applier = MarkdownSourceApplier()
        defer { applier.cancel(); container.dismantle() }
        applier.apply(source: #"A formula: $\frac{1"#, to: container)
        XCTAssertFalse(hasFormula(#"$\frac{1}{2}$"#, in: container))
        applier.apply(source: #"A formula: $\frac{1}{2}$"#, to: container)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && !hasFormula(#"$\frac{1}{2}$"#, in: container) {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertTrue(hasFormula(#"$\frac{1}{2}$"#, in: container))
    }
}
