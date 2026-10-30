import AppKit
import SwiftUI
import XCTest
@testable import agent_deck

@MainActor
final class ComposerInputMethodTests: XCTestCase {
    func testSwiftUIRefreshKeepsMarkedText() throws {
        let state = ComposerTestState()
        let host = NSHostingView(rootView: state.editor())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()

        func findTextView(_ view: NSView) -> DropSafeNSTextView? {
            if let view = view as? DropSafeNSTextView { return view }
            return view.subviews.lazy.compactMap { findTextView($0) }.first
        }
        let editor = try XCTUnwrap(findTextView(host))
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        editor.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        host.rootView = state.editor()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(editor.string, "前文zhong")
        editor.insertText("中", replacementRange: editor.markedRange())
        XCTAssertFalse(editor.hasMarkedText())
        XCTAssertEqual(editor.string, "前文中")
        XCTAssertEqual(state.text, "前文中")
    }

    func testExternalDraftChangeReplacesComposition() throws {
        let state = ComposerTestState()
        let host = NSHostingView(rootView: state.editor())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        let editor = try XCTUnwrap(findComposer(in: host))
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        editor.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        state.text = "另一个草稿"
        host.rootView = state.editor()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(editor.string, "另一个草稿")
        XCTAssertFalse(editor.hasMarkedText())
    }

    func testSessionChangeDoesNotCarryCompositionIntoMatchingDraft() throws {
        let state = ComposerTestState()
        let host = NSHostingView(rootView: state.editor())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        let oldEditor = try XCTUnwrap(findComposer(in: host))
        window.makeFirstResponder(oldEditor)
        oldEditor.setSelectedRange(NSRange(location: oldEditor.string.utf16.count, length: 0))
        oldEditor.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        state.sessionID = UUID()
        state.text = "前文"
        host.rootView = state.editor()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let newEditor = try XCTUnwrap(findComposer(in: host))
        XCTAssertFalse(newEditor === oldEditor)
        XCTAssertEqual(newEditor.string, "前文")
        XCTAssertFalse(newEditor.hasMarkedText())
    }

    private func findComposer(in view: NSView) -> DropSafeNSTextView? {
        if let editor = view as? DropSafeNSTextView { return editor }
        return view.subviews.lazy.compactMap { self.findComposer(in: $0) }.first
    }
    func testMarkedTextKeepsCompositionKeysAwayFromComposerActions() {
        for (characters, keyCode) in [("\r", UInt16(36)), ("\t", 48), ("\u{1b}", 53), ("\u{f700}", 126), ("\u{f701}", 125)] {
            let view = DropSafeNSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
            let handler = KeyHandler()
            handler.active = true
            view.keyHandler = handler
            view.setMarkedText("hello", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertTrue(view.hasMarkedText())

            view.keyDown(with: keyEvent(characters, keyCode: keyCode))

            XCTAssertEqual(handler.actionCount, 0, "Composer intercepted key code \(keyCode) during composition")
        }
    }

    func testReturnSendsAfterCompositionAndAcceptsActiveSuggestion() {
        let view = DropSafeNSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        let handler = KeyHandler()
        view.keyHandler = handler
        view.setMarkedText("hello", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.unmarkText()

        view.keyDown(with: keyEvent("\r", keyCode: 36))
        XCTAssertEqual(handler.sendCount, 1)

        handler.active = true
        view.keyDown(with: keyEvent("\r", keyCode: 36))
        XCTAssertEqual(handler.acceptCount, 1)
        XCTAssertEqual(handler.sendCount, 1)
    }

    private func keyEvent(_ characters: String, keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
                         windowNumber: 0, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }
}

@MainActor
private final class ComposerTestState {
    var text = "前文"
    var attachments: [PiAgentPasteAttachment] = []
    var nextID = 1
    var sessionID = UUID()

    func editor() -> some View {
        PiAgentDropSafeTextEditor(
            text: Binding(get: { self.text }, set: { self.text = $0 }),
            pasteAttachments: Binding(get: { self.attachments }, set: { self.attachments = $0 }),
            nextPasteID: Binding(get: { self.nextID }, set: { self.nextID = $0 }),
            onDropTargeted: { _ in }, onImages: { _ in }, onFiles: { _ in }, onFolders: { _ in },
            onUnsupportedDrop: {}, onSend: {}, onClear: {}, isDisabled: false,
            suggestionKeyBridge: ComposerSuggestionKeyBridge()
        ).id(sessionID)
    }
}

@MainActor
private final class KeyHandler: DropSafeNSTextViewKeyHandler {
    var active = false
    var sendCount = 0
    var acceptCount = 0
    var actionCount = 0

    func send() { sendCount += 1; actionCount += 1 }
    func clear() { actionCount += 1 }
    func suggestionsActive() -> Bool { active }
    func moveSuggestionHighlight(by delta: Int) { actionCount += 1 }
    func acceptSuggestionHighlight() -> Bool { acceptCount += 1; actionCount += 1; return true }
    func dismissSuggestions() { actionCount += 1 }
    func startDictation(in textView: NSTextView) { actionCount += 1 }
}
