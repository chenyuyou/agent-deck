import Foundation
import MathJaxSwift

/// JavaScriptCore and MathJax stay on one background queue, never the UI thread.
nonisolated final class MathJaxRenderer: @unchecked Sendable {
    static let shared = MathJaxRenderer()
    private let queue = DispatchQueue(label: "agent-deck.mathjax", qos: .userInitiated)
    private var engine: MathJax?

    func render(_ latex: String, display: Bool) {
        queue.async { [self] in
            let svg: String?
            do {
                if engine == nil { engine = try MathJax(preferredOutputFormat: .svg) }
                // Avoid HTML, dynamic loading and error-suppression extensions for
                // untrusted transcript text. Unknown commands must remain visible.
                let blocked = Set(["html", "require", "autoload", "noerrors", "noundefined"])
                let packages = TeXInputProcessorOptions.Packages.all.filter { !blocked.contains($0) }
                // MathJaxSwift's default digits pattern has an unescaped dot.
                // It consumes the next non-digit after a number (such as `}`
                // or `\`), breaking valid input like \sum_{i=1} and cases.
                let digits = #"^(?:[0-9]+(?:{,}[0-9]{3})*(?:\.[0-9]*)?|\.[0-9]+)"#
                let input = TeXInputProcessorOptions(loadPackages: packages, digits: digits)
                svg = try engine?.tex2svg(latex, conversionOptions: ConversionOptions(display: display), inputOptions: input)
            } catch {
                svg = nil
            }
            Task { @MainActor in MarkdownMath.mathJaxCompleted(latex: latex, display: display, svg: svg) }
        }
    }
}
