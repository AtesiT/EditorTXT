import SwiftUI
import Combine
import UniformTypeIdentifiers
import AppKit

final class EditorDocument: ObservableObject {
    @Published var text: String = "" {
        didSet {
            isEdited = true
            recomputeStats()
        }
    }

    @Published var fileURL: URL?
    @Published var isEdited: Bool = false

    @Published var searchQuery: String = ""
    @Published var replaceQuery: String = ""
    @Published var isSearchBarVisible: Bool = false
    @Published var isReplaceRowVisible: Bool = false
    @Published var currentMatchIndex: Int = 0
    @Published var matchesCount: Int = 0
    @Published var replaceCurrentTrigger: Int = 0
    @Published var replaceAllTrigger: Int = 0

    @Published private(set) var characterCount: Int = 0
    @Published private(set) var wordCount: Int = 0
    @Published private(set) var lineCount: Int = 1

    var displayName: String {
        fileURL?.lastPathComponent ?? "Untitled"
    }

    private func recomputeStats() {
        var characters = 0
        var words = 0
        var lines = 1
        var inWord = false

        for scalar in text.unicodeScalars {
            characters += 1
            if scalar == "\n" {
                lines += 1
            }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                inWord = false
            } else {
                if !inWord {
                    words += 1
                }
                inWord = true
            }
        }

        characterCount = characters
        wordCount = words
        lineCount = lines
    }

    func newDocument() {
        isSearchBarVisible = false
        isReplaceRowVisible = false
        searchQuery = ""
        replaceQuery = ""

        text = ""
        fileURL = nil
        isEdited = false
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.text, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let content = readTextContent(from: url) else {
            showError("Не удалось открыть файл: неизвестная или неподдерживаемая кодировка.")
            return
        }

        isSearchBarVisible = false
        isReplaceRowVisible = false
        searchQuery = ""
        replaceQuery = ""

        text = content
        fileURL = url
        isEdited = false
    }

    private func readTextContent(from url: URL) -> String? {
        var detectedEncoding: String.Encoding = .utf8
        if let content = try? String(contentsOf: url, usedEncoding: &detectedEncoding) {
            return content
        }

        let fallbackEncodings: [String.Encoding] = [.utf8, .windowsCP1251, .isoLatin1, .utf16]
        for encoding in fallbackEncodings {
            if let content = try? String(contentsOf: url, encoding: encoding) {
                return content
            }
        }

        return nil
    }

    func saveFile() {
        if let url = fileURL {
            if writeToFile(url: url) {
                isEdited = false
            }
        } else {
            saveFileAs()
        }
    }

    func saveFileAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = displayName

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if writeToFile(url: url) {
            self.fileURL = url
            isEdited = false
        }
    }

    @discardableResult
    private func writeToFile(url: URL) -> Bool {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            showError("Не удалось сохранить файл: \(error.localizedDescription)")
            return false
        }
    }

    func confirmDiscardChanges() -> Bool {
        guard isEdited else { return true }

        let alert = NSAlert()
        alert.messageText = "Сохранить изменения перед закрытием?"
        alert.informativeText = "Несохранённые изменения будут потеряны."
        alert.addButton(withTitle: "Сохранить")
        alert.addButton(withTitle: "Не сохранять")
        alert.addButton(withTitle: "Отмена")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            saveFile()
            return !isEdited
        case .alertSecondButtonReturn:
            return true
        default:
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

final class WindowAccessorCoordinator: NSObject, NSWindowDelegate {
    var document: EditorDocument?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        document?.confirmDiscardChanges() ?? true
    }
}

struct WindowAccessor: NSViewRepresentable {
    let document: EditorDocument
    let title: String
    let isEdited: Bool
    let representedURL: URL?

    func makeCoordinator() -> WindowAccessorCoordinator {
        WindowAccessorCoordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view, context: context)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView, context: context)
    }

    private func configure(_ view: NSView, context: Context) {
        guard let window = view.window else { return }

        context.coordinator.document = document
        window.delegate = context.coordinator

        window.title = title
        window.isDocumentEdited = isEdited
        window.representedURL = representedURL
    }
}

struct StatusBarView: View {
    let characterCount: Int
    let wordCount: Int
    let lineCount: Int

    var body: some View {
        HStack {
            Text("Символов: \(characterCount)")
            Divider().frame(height: 12)
            Text("Слов: \(wordCount)")
            Divider().frame(height: 12)
            Text("Строк: \(lineCount)")
            Spacer()
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

struct SearchBarView: View {
    @Binding var searchQuery: String
    let matchesCount: Int
    let currentMatchIndex: Int
    var onNext: () -> Void
    var onPrevious: () -> Void
    var onClose: () -> Void
    var onToggleReplace: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Поиск", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    onNext()
                }

            Text(matchesCount > 0 ? "\(currentMatchIndex + 1)/\(matchesCount)" : "0/0")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(minWidth: 40)

            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
            }
            .keyboardShortcut(.return, modifiers: [.shift])
            .disabled(matchesCount == 0)

            Button(action: onNext) {
                Image(systemName: "chevron.down")
            }
            .disabled(matchesCount == 0)

            Button(action: onToggleReplace) {
                Image(systemName: "arrow.triangle.2.circlepath")
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

struct ReplaceBarView: View {
    @Binding var replaceQuery: String
    var onReplace: () -> Void
    var onReplaceAll: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Заменить на", text: $replaceQuery)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    onReplace()
                }

            Button("Заменить", action: onReplace)
            Button("Заменить всё", action: onReplaceAll)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 40
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let content = textView.string as NSString
        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        var lineNumber = 1
        if characterRange.location > 0 {
            lineNumber = content.substring(to: characterRange.location)
                .components(separatedBy: "\n").count
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { rectForLine, _, _, glyphRangeForLine, _ in
            let charRangeForLine = layoutManager.characterRange(forGlyphRange: glyphRangeForLine, actualGlyphRange: nil)

            let lineRectInScrollView = textView.convert(rectForLine, to: nil)
            let lineRectInRuler = self.convert(lineRectInScrollView, from: nil)

            let numberString = "\(lineNumber)"
            let stringSize = numberString.size(withAttributes: attributes)

            let drawRect = NSRect(
                x: self.ruleThickness - stringSize.width - 6,
                y: lineRectInRuler.minY + (lineRectInRuler.height - stringSize.height) / 2,
                width: stringSize.width,
                height: stringSize.height
            )

            numberString.draw(in: drawRect, withAttributes: attributes)

            if charRangeForLine.location + charRangeForLine.length < content.length {
                lineNumber += 1
            }
        }
    }
}

struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var searchQuery: String
    @Binding var currentMatchIndex: Int
    @Binding var matchesCount: Int
    let isSearchBarVisible: Bool
    let replaceCurrentTrigger: Int
    let replaceAllTrigger: Int
    let replaceQuery: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.delegate = context.coordinator
        textView.string = text
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        let rulerView = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = rulerView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        scrollView.contentView.postsBoundsChangedNotifications = true
        let observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak rulerView] _ in
            rulerView?.needsDisplay = true
        }
        context.coordinator.boundsObserver = observer

        context.coordinator.textView = textView

        return scrollView
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        if let observer = coordinator.boundsObserver {
            NotificationCenter.default.removeObserver(observer)
            coordinator.boundsObserver = nil
        }
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        if context.coordinator.lastReplaceCurrentTrigger != replaceCurrentTrigger {
            context.coordinator.lastReplaceCurrentTrigger = replaceCurrentTrigger
            context.coordinator.replaceCurrentMatch(
                textView: textView,
                replaceQuery: replaceQuery,
                query: searchQuery,
                currentMatchIndex: currentMatchIndex
            )
        }

        if context.coordinator.lastReplaceAllTrigger != replaceAllTrigger {
            context.coordinator.lastReplaceAllTrigger = replaceAllTrigger
            context.coordinator.replaceAllMatches(
                textView: textView,
                replaceQuery: replaceQuery,
                query: searchQuery
            )
        }

        guard isSearchBarVisible, !searchQuery.isEmpty else {
            context.coordinator.clearHighlightIfNeeded(textView: textView)
            context.coordinator.reportMatchesCountIfNeeded(0) { count in
                matchesCount = count
            }
            return
        }

        let ranges: [NSRange]
        if context.coordinator.cachedSearchedText == textView.string,
           context.coordinator.cachedQuery == searchQuery {
            ranges = context.coordinator.cachedRanges
        } else {
            ranges = context.coordinator.matches(in: textView.string, query: searchQuery)
            context.coordinator.cachedSearchedText = textView.string
            context.coordinator.cachedQuery = searchQuery
            context.coordinator.cachedRanges = ranges
        }

        context.coordinator.highlightIfNeeded(textView: textView, ranges: ranges, currentMatchIndex: currentMatchIndex)
        context.coordinator.reportMatchesCountIfNeeded(ranges.count) { count in
            matchesCount = count
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorTextView
        weak var textView: NSTextView?

        var boundsObserver: NSObjectProtocol?

        var cachedSearchedText: String?
        var cachedQuery: String?
        var cachedRanges: [NSRange] = []

        var lastReportedMatchesCount: Int = -1

        var isHighlightCleared = true
        var lastHighlightedRanges: [NSRange] = []
        var lastHighlightedIndex: Int = -1

        var lastReplaceCurrentTrigger: Int = 0
        var lastReplaceAllTrigger: Int = 0

        init(_ parent: EditorTextView) {
            self.parent = parent
        }

        deinit {
            if let observer = boundsObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func matches(in text: String, query: String) -> [NSRange] {
            guard !query.isEmpty else { return [] }

            var ranges: [NSRange] = []
            let nsText = text as NSString
            var searchRange = NSRange(location: 0, length: nsText.length)

            while true {
                let foundRange = nsText.range(
                    of: query,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchRange
                )
                if foundRange.location == NSNotFound { break }

                ranges.append(foundRange)

                let nextLocation = foundRange.location + foundRange.length
                guard nextLocation < nsText.length else { break }
                searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
            }

            return ranges
        }

        func highlightIfNeeded(textView: NSTextView, ranges: [NSRange], currentMatchIndex: Int) {
            if ranges == lastHighlightedRanges && currentMatchIndex == lastHighlightedIndex {
                return
            }
            highlight(textView: textView, ranges: ranges, currentMatchIndex: currentMatchIndex)
            lastHighlightedRanges = ranges
            lastHighlightedIndex = currentMatchIndex
            isHighlightCleared = ranges.isEmpty
        }

        private func highlight(textView: NSTextView, ranges: [NSRange], currentMatchIndex: Int) {
            guard let textStorage = textView.textStorage else { return }

            textStorage.beginEditing()
            textStorage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: textStorage.length))

            for (index, range) in ranges.enumerated() {
                let color: NSColor = index == currentMatchIndex ? .systemOrange : .systemYellow
                textStorage.addAttribute(.backgroundColor, value: color, range: range)
            }

            textStorage.endEditing()
        }

        func clearHighlightIfNeeded(textView: NSTextView) {
            lastHighlightedRanges = []
            lastHighlightedIndex = -1

            if !isHighlightCleared, let textStorage = textView.textStorage {
                textStorage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: textStorage.length))
            }
            isHighlightCleared = true

            cachedSearchedText = nil
            cachedQuery = nil
            cachedRanges = []
        }

        func invalidateHighlightCache() {
            cachedSearchedText = nil
            cachedQuery = nil
            cachedRanges = []
            lastHighlightedRanges = []
            lastHighlightedIndex = -1
        }

        func reportMatchesCountIfNeeded(_ count: Int, onChange: @escaping (Int) -> Void) {
            guard count != lastReportedMatchesCount else { return }
            lastReportedMatchesCount = count
            DispatchQueue.main.async {
                onChange(count)
            }
        }

        func replaceCurrentMatch(textView: NSTextView, replaceQuery: String, query: String, currentMatchIndex: Int) {
            let ranges = matches(in: textView.string, query: query)
            guard currentMatchIndex >= 0, currentMatchIndex < ranges.count else { return }

            performReplace(textView: textView, ranges: [ranges[currentMatchIndex]], with: replaceQuery)
            invalidateHighlightCache()
        }

        func replaceAllMatches(textView: NSTextView, replaceQuery: String, query: String) {
            let ranges = matches(in: textView.string, query: query)
            guard !ranges.isEmpty else { return }

            performReplace(textView: textView, ranges: ranges, with: replaceQuery)
            invalidateHighlightCache()
        }

        private func performReplace(textView: NSTextView, ranges: [NSRange], with replacement: String) {
            guard let textStorage = textView.textStorage else { return }

            textStorage.beginEditing()
            for range in ranges.sorted(by: { $0.location > $1.location }) {
                textStorage.replaceCharacters(in: range, with: replacement)
            }
            textStorage.endEditing()

            textView.didChangeText()
        }
    }
}

struct ContentView: View {
    @StateObject private var document = EditorDocument()

    var body: some View {
        VStack(spacing: 0) {
            if document.isSearchBarVisible {
                SearchBarView(
                    searchQuery: $document.searchQuery,
                    matchesCount: document.matchesCount,
                    currentMatchIndex: document.currentMatchIndex,
                    onNext: {
                        guard document.matchesCount > 0 else { return }
                        document.currentMatchIndex = (document.currentMatchIndex + 1) % document.matchesCount
                    },
                    onPrevious: {
                        guard document.matchesCount > 0 else { return }
                        document.currentMatchIndex = (document.currentMatchIndex - 1 + document.matchesCount) % document.matchesCount
                    },
                    onClose: {
                        document.isSearchBarVisible = false
                        document.isReplaceRowVisible = false
                        document.searchQuery = ""
                    },
                    onToggleReplace: {
                        document.isReplaceRowVisible.toggle()
                    }
                )

                if document.isReplaceRowVisible {
                    ReplaceBarView(
                        replaceQuery: $document.replaceQuery,
                        onReplace: {
                            document.replaceCurrentTrigger += 1
                        },
                        onReplaceAll: {
                            document.replaceAllTrigger += 1
                        }
                    )
                }

                Divider()
            }

            EditorTextView(
                text: $document.text,
                searchQuery: $document.searchQuery,
                currentMatchIndex: $document.currentMatchIndex,
                matchesCount: $document.matchesCount,
                isSearchBarVisible: document.isSearchBarVisible,
                replaceCurrentTrigger: document.replaceCurrentTrigger,
                replaceAllTrigger: document.replaceAllTrigger,
                replaceQuery: document.replaceQuery
            )

            Divider()

            StatusBarView(
                characterCount: document.characterCount,
                wordCount: document.wordCount,
                lineCount: document.lineCount
            )
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { document.newDocument() }) {
                    Image(systemName: "doc.badge.plus")
                }
                Button(action: { document.openFile() }) {
                    Image(systemName: "folder")
                }
                Button(action: { document.saveFile() }) {
                    Image(systemName: "square.and.arrow.down")
                }
                Button(action: {
                    document.isSearchBarVisible.toggle()
                }) {
                    Image(systemName: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
        .background(
            WindowAccessor(
                document: document,
                title: document.displayName,
                isEdited: document.isEdited,
                representedURL: document.fileURL
            )
        )
    }
}
