import SwiftUI
import Combine
import UniformTypeIdentifiers
import AppKit

final class EditorDocument: ObservableObject {
    @Published var text: String = "" {
        didSet {
            guard !isLoading else {
                recomputeStats()
                return
            }
            isEdited = true
            recomputeStats()
        }
    }
    @Published var fileURL: URL?
    @Published var isEdited: Bool = false
    @Published var searchQuery: String = "" {
        didSet {
            currentMatchIndex = 0
        }
    }
    @Published var replaceQuery: String = ""
    @Published var isSearchBarVisible: Bool = false {
        didSet {
            if !isSearchBarVisible {
                searchQuery = ""
                isReplaceRowVisible = false
            }
        }
    }
    @Published var isReplaceRowVisible: Bool = false
    @Published var currentMatchIndex: Int = 0
    @Published var matchesCount: Int = 0 {
        didSet {
            if matchesCount == 0 {
                currentMatchIndex = 0
            } else if currentMatchIndex >= matchesCount {
                currentMatchIndex = matchesCount - 1
            }
        }
    }
    @Published var replaceCurrentTrigger: Int = 0
    @Published var replaceAllTrigger: Int = 0

    @Published private(set) var characterCount: Int = 0
    @Published private(set) var wordCount: Int = 0
    @Published private(set) var lineCount: Int = 1

    private var isLoading = false

    var displayName: String {
        fileURL?.lastPathComponent ?? "Untitled"
    }

    private func recomputeStats() {
        var chars = 0
        var words = 0
        var lines = 1
        var inWord = false

        for character in text {
            chars += 1

            if character.isNewline {
                lines += 1
            }

            if character.isWhitespace || character.isNewline {
                inWord = false
            } else if !inWord {
                inWord = true
                words += 1
            }
        }

        characterCount = chars
        wordCount = words
        lineCount = text.isEmpty ? 1 : lines
    }

    func newDocument() {
        guard confirmDiscardChanges() else { return }
        isLoading = true
        text = ""
        fileURL = nil
        isEdited = false
        isLoading = false
    }

    func openFile() {
        guard confirmDiscardChanges() else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                isLoading = true
                self.text = content
                self.fileURL = url
                self.isEdited = false
                isLoading = false
            } catch {
                showError("Не удалось открыть файл: \(error.localizedDescription)")
            }
        }
    }

    func saveFile() {
        if let url = fileURL {
            writeToFile(url: url)
        } else {
            saveFileAs()
        }
    }

    func saveFileAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "Untitled.txt"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            if writeToFile(url: url) {
                self.fileURL = url
            }
        }
    }

    func confirmDiscardChanges() -> Bool {
        guard isEdited else { return true }

        let alert = NSAlert()
        alert.messageText = "Сохранить изменения?"
        alert.informativeText = "В документе есть несохранённые изменения."
        alert.addButton(withTitle: "Сохранить")
        alert.addButton(withTitle: "Не сохранять")
        alert.addButton(withTitle: "Отмена")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            saveFile()
            return !isEdited
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func goToNextMatch() {
        guard matchesCount > 0 else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matchesCount
    }

    func goToPreviousMatch() {
        guard matchesCount > 0 else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matchesCount) % matchesCount
    }

    func replaceCurrentMatch() {
        replaceCurrentTrigger += 1
    }

    func replaceAllMatches() {
        replaceAllTrigger += 1
    }

    @discardableResult
    private func writeToFile(url: URL) -> Bool {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            isEdited = false
            return true
        } catch {
            showError("Не удалось сохранить файл: \(error.localizedDescription)")
            return false
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Ошибка"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private final class WindowDelegateCoordinator: NSObject, NSWindowDelegate {
    var document: EditorDocument?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        document?.confirmDiscardChanges() ?? true
    }
}

private struct WindowCloseHandler: NSViewRepresentable {
    let document: EditorDocument

    func makeCoordinator() -> WindowDelegateCoordinator {
        WindowDelegateCoordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.document = document
            view.window?.delegate = context.coordinator
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.document = document
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    let title: String
    let isEdited: Bool
    let representedURL: URL?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSView) {
        guard let window = view.window else { return }
        window.title = title
        window.isDocumentEdited = isEdited
        window.representedURL = representedURL
    }
}

private struct StatusBarView: View {
    let characterCount: Int
    let wordCount: Int
    let lineCount: Int

    var body: some View {
        HStack {
            Text("Строк: \(lineCount)")
            Divider().frame(height: 12)
            Text("Слов: \(wordCount)")
            Divider().frame(height: 12)
            Text("Символов: \(characterCount)")
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SearchBarView: View {
    @Binding var searchQuery: String
    let currentMatchIndex: Int
    let matchesCount: Int
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void

    @FocusState private var isFocused: Bool

    private var matchesLabel: String {
        matchesCount == 0 ? "Нет совпадений" : "\(currentMatchIndex + 1) из \(matchesCount)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Найти", text: $searchQuery)
                .textFieldStyle(.plain)
                .focused($isFocused)

            Text(matchesLabel)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(minWidth: 90, alignment: .trailing)

            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(matchesCount == 0)

            Button(action: onNext) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(matchesCount == 0)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Button(action: onNext) {
                EmptyView()
            }
            .keyboardShortcut(.return, modifiers: [])
            .frame(width: 0, height: 0)
            .hidden()

            Button(action: onPrevious) {
                EmptyView()
            }
            .keyboardShortcut(.return, modifiers: [.shift])
            .frame(width: 0, height: 0)
            .hidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            isFocused = true
        }
    }
}

private struct ReplaceBarView: View {
    @Binding var replaceQuery: String
    let isReplaceDisabled: Bool
    let onReplace: () -> Void
    let onReplaceAll: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundColor(.secondary)

            TextField("Заменить на", text: $replaceQuery)
                .textFieldStyle(.plain)

            Spacer()

            Button("Заменить", action: onReplace)
                .disabled(isReplaceDisabled)

            Button("Заменить всё", action: onReplaceAll)
                .disabled(isReplaceDisabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?
    var font: NSFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    var textColor: NSColor = NSColor.secondaryLabelColor.withAlphaComponent(0.4)

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 36
    }

    required init(coder: NSCoder) {
        fatalError()
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let relativePoint = convert(NSPoint.zero, from: textView)
        let containerInset = textView.textContainerInset.height
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]

        func drawNumber(_ number: Int, forLineRect lineRect: NSRect) {
            let string = "\(number)" as NSString
            let size = string.size(withAttributes: attributes)
            let x = ruleThickness - size.width - 6
            let y = relativePoint.y + containerInset + lineRect.minY + (lineRect.height - size.height) / 2.0
            string.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
        }

        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textContainer)
        let firstVisibleCharacterIndex = layoutManager.characterIndexForGlyph(at: visibleGlyphRange.location)

        let content = textView.string as NSString
        var lineNumber = content.substring(to: firstVisibleCharacterIndex).components(separatedBy: "\n").count

        var glyphIndex = visibleGlyphRange.location

        while glyphIndex < NSMaxRange(visibleGlyphRange) {
            let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let lineCharacterRange = content.lineRange(for: NSRange(location: characterIndex, length: 0))
            let lineGlyphRange = layoutManager.glyphRange(forCharacterRange: lineCharacterRange, actualCharacterRange: nil)

            var effectiveRange = NSRange(location: 0, length: 0)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: lineGlyphRange.location, effectiveRange: &effectiveRange)

            drawNumber(lineNumber, forLineRect: lineRect)

            lineNumber += 1
            glyphIndex = NSMaxRange(lineGlyphRange)
        }

        if layoutManager.extraLineFragmentTextContainer != nil {
            drawNumber(lineNumber, forLineRect: layoutManager.extraLineFragmentRect)
        }
    }
}

private struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    var isSearchBarVisible: Bool
    var searchQuery: String
    var replaceQuery: String
    var currentMatchIndex: Int
    var replaceCurrentTrigger: Int
    var replaceAllTrigger: Int
    var onMatchesCountChange: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.textColor = NSColor.labelColor

        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        let rulerView = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = rulerView

        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak rulerView] _ in
            rulerView?.needsDisplay = true
        }

        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.rulerView = rulerView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            coordinator.rulerView?.needsDisplay = true
        }

        if replaceCurrentTrigger != coordinator.lastReplaceCurrentTrigger {
            coordinator.lastReplaceCurrentTrigger = replaceCurrentTrigger
            let query = searchQuery
            let replacement = replaceQuery
            let index = currentMatchIndex
            DispatchQueue.main.async {
                coordinator.replaceCurrentMatch(in: textView, query: query, replacement: replacement, index: index)
            }
        }

        if replaceAllTrigger != coordinator.lastReplaceAllTrigger {
            coordinator.lastReplaceAllTrigger = replaceAllTrigger
            let query = searchQuery
            let replacement = replaceQuery
            DispatchQueue.main.async {
                coordinator.replaceAllMatches(in: textView, query: query, replacement: replacement)
            }
        }

        guard isSearchBarVisible, !searchQuery.isEmpty else {
            coordinator.clearHighlightIfNeeded(textView: textView)
            coordinator.reportMatchesCountIfNeeded(0, onChange: onMatchesCountChange)
            return
        }

        let ranges: [NSRange]
        if coordinator.cachedSearchedText == textView.string && coordinator.cachedQuery == searchQuery {
            ranges = coordinator.cachedRanges
        } else {
            ranges = coordinator.matches(in: textView.string, query: searchQuery)
            coordinator.cachedSearchedText = textView.string
            coordinator.cachedQuery = searchQuery
            coordinator.cachedRanges = ranges
        }

        coordinator.highlightIfNeeded(textView: textView, ranges: ranges, currentMatchIndex: currentMatchIndex)
        coordinator.reportMatchesCountIfNeeded(ranges.count, onChange: onMatchesCountChange)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        if let observer = coordinator.boundsObserver {
            NotificationCenter.default.removeObserver(observer)
            coordinator.boundsObserver = nil
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: NSTextView?
        weak var rulerView: LineNumberRulerView?
        var lastReplaceCurrentTrigger: Int = 0
        var lastReplaceAllTrigger: Int = 0
        var boundsObserver: NSObjectProtocol?

        var cachedSearchedText: String?
        var cachedQuery: String?
        var cachedRanges: [NSRange] = []
        private var lastReportedMatchesCount: Int = -1
        private var isHighlightCleared = true

        private var lastHighlightedRanges: [NSRange] = []
        private var lastHighlightedIndex: Int = -1

        init(text: Binding<String>) {
            self.text = text
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            rulerView?.needsDisplay = true
        }

        func matches(in content: String, query: String) -> [NSRange] {
            guard !query.isEmpty else { return [] }

            let nsContent = content as NSString
            var ranges: [NSRange] = []
            var searchRange = NSRange(location: 0, length: nsContent.length)

            while searchRange.location < nsContent.length {
                let foundRange = nsContent.range(of: query, options: .caseInsensitive, range: searchRange)
                if foundRange.location == NSNotFound { break }

                ranges.append(foundRange)

                let nextLocation = foundRange.location + foundRange.length
                searchRange = NSRange(location: nextLocation, length: nsContent.length - nextLocation)
            }

            return ranges
        }

        func highlightIfNeeded(textView: NSTextView, ranges: [NSRange], currentMatchIndex: Int) {
            guard ranges != lastHighlightedRanges || currentMatchIndex != lastHighlightedIndex else {
                return
            }

            highlight(textView: textView, ranges: ranges, currentMatchIndex: currentMatchIndex)

            lastHighlightedRanges = ranges
            lastHighlightedIndex = currentMatchIndex
        }

        private func highlight(textView: NSTextView, ranges: [NSRange], currentMatchIndex: Int) {
            guard let layoutManager = textView.layoutManager else { return }

            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
            isHighlightCleared = false

            for (index, range) in ranges.enumerated() {
                let color: NSColor = index == currentMatchIndex
                    ? NSColor.orange
                    : NSColor.orange.withAlphaComponent(0.35)
                layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
            }

            if ranges.indices.contains(currentMatchIndex) {
                textView.scrollRangeToVisible(ranges[currentMatchIndex])
            }
        }

        func clearHighlightIfNeeded(textView: NSTextView) {
            lastHighlightedRanges = []
            lastHighlightedIndex = -1

            guard !isHighlightCleared, let layoutManager = textView.layoutManager else { return }
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
            isHighlightCleared = true
            cachedSearchedText = nil
            cachedQuery = nil
            cachedRanges = []
        }

        func reportMatchesCountIfNeeded(_ count: Int, onChange: @escaping (Int) -> Void) {
            guard count != lastReportedMatchesCount else { return }
            lastReportedMatchesCount = count
            DispatchQueue.main.async {
                onChange(count)
            }
        }

        func replaceCurrentMatch(in textView: NSTextView, query: String, replacement: String, index: Int) {
            let ranges = matches(in: textView.string, query: query)
            guard ranges.indices.contains(index) else { return }

            performReplace(in: textView, range: ranges[index], with: replacement, actionName: "Replace")
        }

        func replaceAllMatches(in textView: NSTextView, query: String, replacement: String) {
            let ranges = matches(in: textView.string, query: query)
            guard !ranges.isEmpty else { return }

            textView.undoManager?.beginUndoGrouping()
            textView.undoManager?.setActionName("Replace All")

            for range in ranges.reversed() {
                if textView.shouldChangeText(in: range, replacementString: replacement) {
                    textView.textStorage?.replaceCharacters(in: range, with: replacement)
                    textView.didChangeText()
                }
            }

            textView.undoManager?.endUndoGrouping()
            rulerView?.needsDisplay = true
            invalidateHighlightCache()
        }

        private func performReplace(in textView: NSTextView, range: NSRange, with replacement: String, actionName: String) {
            textView.undoManager?.beginUndoGrouping()
            textView.undoManager?.setActionName(actionName)

            if textView.shouldChangeText(in: range, replacementString: replacement) {
                textView.textStorage?.replaceCharacters(in: range, with: replacement)
                textView.didChangeText()
            }

            textView.undoManager?.endUndoGrouping()
            rulerView?.needsDisplay = true
            invalidateHighlightCache()
        }

        private func invalidateHighlightCache() {
            lastHighlightedRanges = []
            lastHighlightedIndex = -1
            cachedSearchedText = nil
            cachedQuery = nil
            cachedRanges = []
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var document: EditorDocument

    var body: some View {
        VStack(spacing: 0) {
            EditorTextView(
                text: $document.text,
                isSearchBarVisible: document.isSearchBarVisible,
                searchQuery: document.searchQuery,
                replaceQuery: document.replaceQuery,
                currentMatchIndex: document.currentMatchIndex,
                replaceCurrentTrigger: document.replaceCurrentTrigger,
                replaceAllTrigger: document.replaceAllTrigger,
                onMatchesCountChange: { count in
                    document.matchesCount = count
                }
            )

            if document.isSearchBarVisible {
                Divider()
                SearchBarView(
                    searchQuery: $document.searchQuery,
                    currentMatchIndex: document.currentMatchIndex,
                    matchesCount: document.matchesCount,
                    onNext: { document.goToNextMatch() },
                    onPrevious: { document.goToPreviousMatch() },
                    onClose: { document.isSearchBarVisible = false }
                )

                if document.isReplaceRowVisible {
                    Divider()
                    ReplaceBarView(
                        replaceQuery: $document.replaceQuery,
                        isReplaceDisabled: document.matchesCount == 0,
                        onReplace: { document.replaceCurrentMatch() },
                        onReplaceAll: { document.replaceAllMatches() }
                    )
                }
            }

            Divider()

            StatusBarView(
                characterCount: document.characterCount,
                wordCount: document.wordCount,
                lineCount: document.lineCount
            )
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(
            ZStack {
                WindowConfigurator(
                    title: document.displayName,
                    isEdited: document.isEdited,
                    representedURL: document.fileURL
                )
                WindowCloseHandler(document: document)
            }
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(EditorDocument())
}
