import AppKit
import SwiftMath

/// Typesets complete math spans while leaving unfinished, unsupported, and code spans intact.
@MainActor
enum MarkdownMath {
    static let sourceAttribute = NSAttributedString.Key("AgentDeckMathSource")
    struct Formula {
        let placeholder: String
        let original: String
        let image: NSImage
        let descent: CGFloat
        let display: Bool
    }
    struct Prepared {
        let text: String
        let formulas: [Formula]
        var isStandaloneDisplay: Bool {
            guard formulas.count == 1, let formula = formulas.first, formula.display else { return false }
            return text.trimmingCharacters(in: .whitespacesAndNewlines) == formula.placeholder
        }
    }

    // Explicit TeX delimiters, dollar delimiters, and a conservative multiline
    // bracket form emitted by some models. Never recognize plain [links].
    private static let expressions: [(String, Bool)] = [
        (#"(?s)\$\$(.+?)\$\$"#, true),
        (#"(?s)\\\[(.+?)\\\]"#, true),
        (#"(?s)\\\((.+?)\\\)"#, false),
        (#"(?m)^\[\s*\n([\s\S]*?)\n\s*\]$"#, true),
        (#"(?<![\\\$0-9])\$(?!\s|\$)([^\n$]+?)(?<!\s)\$(?![\d$])"#, false),
        (#"(?s)(?<!\\)(\\begin\{(equation\*?|align\*?|alignat\*?|gather\*?|multline\*?|flalign\*?|split|cases|matrix|pmatrix|bmatrix|Bmatrix|vmatrix|Vmatrix)\}.*?\\end\{\2\})"#, true)
    ]

    static let mathJaxUpdated = Notification.Name("AgentDeckMathJaxUpdated")
    static private(set) var mathJaxRevision = 0
    private static var mathJaxSVG: [String: String] = [:]
    private static var mathJaxPending: Set<String> = []
    private static var mathJaxFailed: Set<String> = []
    private static var mathJaxFailedOrder: [String] = []
    private static var mathJaxOrder: [String] = []
    private static var updatedFormulae: Set<String> = []
    private static var updateTask: Task<Void, Never>?

    private static func mathJaxKey(_ latex: String, display: Bool) -> String { "\(display)|\(latex)" }

#if DEBUG
    static func mathJaxTestState(_ latex: String, display: Bool) -> String {
        let key = mathJaxKey(latex, display: display)
        if mathJaxSVG[key] != nil { return "rendered" }
        if mathJaxFailed.contains(key) { return "failed" }
        return "pending"
    }
#endif

    static func mathJaxCompleted(latex: String, display: Bool, svg: String?) {
        let key = mathJaxKey(latex, display: display)
        mathJaxPending.remove(key)
        guard let svg else {
            mathJaxFailed.insert(key)
            mathJaxFailedOrder.append(key)
            if mathJaxFailedOrder.count > 128 { mathJaxFailed.remove(mathJaxFailedOrder.removeFirst()) }
            return
        }
        mathJaxSVG[key] = svg
        mathJaxOrder.append(key)
        if mathJaxOrder.count > 128 { mathJaxSVG.removeValue(forKey: mathJaxOrder.removeFirst()) }
        updatedFormulae.insert(latex)
        guard updateTask == nil else { return }
        updateTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            let formulas = updatedFormulae
            updatedFormulae.removeAll()
            updateTask = nil
            mathJaxRevision &+= 1
            NotificationCenter.default.post(name: mathJaxUpdated, object: Array(formulas))
        }
    }

    private static var imageCache: [String: (NSImage, CGFloat)] = [:]
    private static var imageCacheOrder: [String] = []
    private static let imageCacheLimit = 128

    private static let codeRegex = try! NSRegularExpression(pattern: #"(?s)(`+).*?\1"#)
    private static let regexes = expressions.map { (try! NSRegularExpression(pattern: $0.0), $0.0, $0.1) }

    static func prepare(_ source: String, font: NSFont, color: NSColor) -> Prepared {
        guard source.contains("$") || source.contains("\\(") || source.contains("\\[") || source.contains("\\begin{") || (source.contains("[") && source.contains("\n")) else {
            return Prepared(text: source, formulas: [])
        }
        let nsSource = source as NSString
        let full = NSRange(location: 0, length: nsSource.length)
        let codeRanges = codeRegex.matches(in: source, range: full).map(\.range)
        var candidates: [(NSRange, String, Bool)] = []
        for (regex, pattern, display) in regexes {
            for match in regex.matches(in: source, range: full) {
                guard match.numberOfRanges > 1,
                      !codeRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                      !candidates.contains(where: { NSIntersectionRange($0.0, match.range).length > 0 }) else { continue }
                let latex = nsSource.substring(with: match.range(at: 1))
                // Bare brackets are accepted only for a multiline expression with
                // explicit TeX commands, so ordinary bracketed prose stays intact.
                if pattern.hasPrefix("(?m)") && !latex.contains("\\") { continue }
                candidates.append((match.range, latex, display))
            }
        }
        let result = NSMutableString(string: source)
        var formulas: [Formula] = []
        for (range, latex, display) in candidates.sorted(by: { $0.0.location > $1.0.location }) {
            guard !latex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, latex.count <= 4_000 else { continue }
            let key = mathJaxKey(latex, display: display)
            // Long text in a box must keep AppKit's readable wrapping.
            let plainBox = unwrap(latex, command: "boxed").flatMap { unwrap($0, command: "text") }
            let useNativeTextBox = plainBox.map { !$0.contains("\\") && !$0.contains("{") && !$0.contains("}") } ?? false
            if !useNativeTextBox, mathJaxSVG[key] == nil, !mathJaxPending.contains(key), !mathJaxFailed.contains(key) {
                mathJaxPending.insert(key)
                MathJaxRenderer.shared.render(latex, display: display)
            }
            let svg = useNativeTextBox ? nil : mathJaxSVG[key]
            let cacheKey = "\(ThemeManager.shared.revision)|\(font.pointSize)|\(color.description)|\(display)|\(svg == nil ? "native" : "mathjax")|\(latex)"
            let rendered: (NSImage, CGFloat)
            if let cached = imageCache[cacheKey] {
                rendered = cached
            } else {
                guard let image = svg.flatMap({ svgImage($0, font: font, color: color) }) ?? render(latex: latex, font: font, color: color, display: display) else { continue }
                rendered = image
                imageCache[cacheKey] = rendered
                imageCacheOrder.append(cacheKey)
                if imageCacheOrder.count > imageCacheLimit { imageCache.removeValue(forKey: imageCacheOrder.removeFirst()) }
            }
            let placeholder = "AGENTDECKMATH\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))END"
            formulas.append(Formula(placeholder: placeholder, original: nsSource.substring(with: range), image: rendered.0, descent: rendered.1, display: display))
            result.replaceCharacters(in: range, with: placeholder)
        }
        return Prepared(text: result as String, formulas: formulas)
    }

    private static func svgImage(_ svg: String, font: NSFont, color: NSColor) -> (NSImage, CGFloat)? {
        var source = svg
        let units = try! NSRegularExpression(pattern: #"(width|height)="([0-9.]+)ex""#)
        let original = source as NSString
        for match in units.matches(in: source, range: NSRange(location: 0, length: original.length)).reversed() {
            let name = original.substring(with: match.range(at: 1))
            guard let number = Double(original.substring(with: match.range(at: 2))), let range = Range(match.range, in: source) else { return nil }
            source.replaceSubrange(range, with: "\(name)=\"\(number * Double(font.pointSize) / 2)px\"")
        }
        let resolved = color.usingColorSpace(.deviceRGB) ?? NSColor.labelColor.usingColorSpace(.deviceRGB)
        guard let resolved else { return nil }
        let rgb = String(format: "#%02X%02X%02X", Int(resolved.redComponent * 255), Int(resolved.greenComponent * 255), Int(resolved.blueComponent * 255))
        source = source.replacingOccurrences(of: "currentColor", with: rgb)
        guard let image = NSImage(data: Data(source.utf8)), image.size.width > 0, image.size.height > 0 else { return nil }
        let descent: CGFloat
        if let regex = try? NSRegularExpression(pattern: #"vertical-align:\s*-([0-9.]+)ex"#),
           let match = regex.firstMatch(in: svg, range: NSRange(location: 0, length: (svg as NSString).length)),
           let value = Double((svg as NSString).substring(with: match.range(at: 1))) {
            descent = CGFloat(value) * font.pointSize / 2
        } else { descent = 0 }
        return (image, descent)
    }

    /// SwiftMath does not implement `\boxed`. Render a complete outer box
    /// ourselves while leaving malformed or unsupported content as source.
    private static func render(latex: String, font: NSFont, color: NSColor, display: Bool) -> (NSImage, CGFloat)? {
        if let boxed = unwrap(latex, command: "boxed") {
            if let text = unwrap(boxed, command: "text"), !text.contains("\\"), !text.contains("{") && !text.contains("}") {
                return (wrappedTextBox(text, font: font, color: color), 0)
            }
            guard let (content, descent) = render(latex: boxed, font: font, color: color, display: display) else { return nil }
            let inset: CGFloat = 8
            let size = NSSize(width: content.size.width + inset * 2, height: content.size.height + inset * 2)
            let image = NSImage(size: size, flipped: false) { _ in
                color.setStroke()
                NSBezierPath(rect: NSRect(x: 0.5, y: 0.5, width: size.width - 1, height: size.height - 1)).stroke()
                content.draw(in: NSRect(x: inset, y: inset, width: content.size.width, height: content.size.height))
                return true
            }
            return (image, descent + inset)
        }
        var renderer = MathImage(latex: latex, fontSize: font.pointSize, textColor: color, labelMode: display ? .display : .text)
        let (error, image, layout) = renderer.asImage()
        guard error == nil, let image, let layout, image.size.width > 0, image.size.height > 0 else { return nil }
        return (image, layout.descent)
    }

    private static func unwrap(_ source: String, command: String) -> String? {
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "\\\(command)"
        guard text.hasPrefix(prefix) else { return nil }
        var index = text.index(text.startIndex, offsetBy: prefix.count)
        while index < text.endIndex && text[index].isWhitespace { index = text.index(after: index) }
        guard index < text.endIndex, text[index] == "{" else { return nil }
        let start = text.index(after: index)
        var depth = 1
        var escaped = false
        index = start
        while index < text.endIndex {
            let character = text[index]
            if escaped { escaped = false }
            else if character == "\\" { escaped = true }
            else if character == "{" { depth += 1 }
            else if character == "}" {
                depth -= 1
                if depth == 0 {
                    let remainder = text[text.index(after: index)...].trimmingCharacters(in: .whitespacesAndNewlines)
                    return remainder.isEmpty ? String(text[start..<index]) : nil
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Text inside a box can contain long Chinese or English sentences. Use
    /// AppKit's text layout so it wraps without shrinking the font.
    private static func wrappedTextBox(_ text: String, font: NSFont, color: NSColor) -> NSImage {
        let inset: CGFloat = 10
        let maxTextWidth: CGFloat = 400
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let content = NSAttributedString(string: text, attributes: attributes)
        let bounds = content.boundingRect(with: NSSize(width: maxTextWidth, height: 100_000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let textWidth = min(maxTextWidth, max(1, ceil(bounds.width)))
        let size = NSSize(width: textWidth + inset * 2, height: max(1, ceil(bounds.height)) + inset * 2)
        return NSImage(size: size, flipped: true) { _ in
            color.setStroke()
            NSBezierPath(rect: NSRect(x: 0.5, y: 0.5, width: size.width - 1, height: size.height - 1)).stroke()
            content.draw(with: NSRect(x: inset, y: inset, width: textWidth, height: size.height - inset * 2), options: [.usesLineFragmentOrigin, .usesFontLeading])
            return true
        }
    }

    static func apply(_ prepared: Prepared, to attributed: NSMutableAttributedString) {
        for formula in prepared.formulas {
            let range = (attributed.string as NSString).range(of: formula.placeholder)
            guard range.location != NSNotFound else { continue }
            let attachment = MathTextAttachment()
            attachment.image = formula.image
            attachment.bounds = NSRect(x: 0, y: -formula.descent, width: formula.image.size.width, height: formula.image.size.height)
            let replacement = NSMutableAttributedString(attachment: attachment)
            let originalAttributes = attributed.attributes(at: range.location, effectiveRange: nil)
            replacement.addAttributes(originalAttributes, range: NSRange(location: 0, length: replacement.length))
            replacement.addAttribute(sourceAttribute, value: formula.original, range: NSRange(location: 0, length: replacement.length))
            attributed.replaceCharacters(in: range, with: replacement)
        }
    }
}

/// Prevent wide formulas from being clipped when the transcript pane is narrow.
private nonisolated final class MathTextAttachment: NSTextAttachment {
    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: NSRect, glyphPosition: NSPoint, characterIndex: Int) -> NSRect {
        guard lineFrag.width > 1, bounds.width > lineFrag.width else { return bounds }
        let scale = lineFrag.width / bounds.width
        return NSRect(x: bounds.origin.x, y: bounds.origin.y * scale, width: lineFrag.width, height: bounds.height * scale)
    }
}
