import SwiftUI
import Combine
import UniformTypeIdentifiers
import AppKit

final class EditorDocument: ObservableObject {
    @Published var text: String = "" {
        didSet {
            guard !isLoading else { return }
            isEdited = true
        }
    }
    @Published var fileURL: URL?
    @Published var isEdited: Bool = false
    @Published var searchQuery: String = "" {
        didSet {
            currentMatchIndex = 0
        }
    }
    @Published var isSearchBarVisible: Bool = false {
        didSet {
            if !isSearchBarVisible {
                searchQuery = ""
            }
        }
    }
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

    private var isLoading = false

    var displayName: String {
        fileURL?.lastPathComponent ?? "Untitled"
    }

    var characterCount: Int {
        text.count
    }

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    var lineCount: Int {
        text.isEmpty ? 1 : text.components(separatedBy: .newlines).count
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
            writeToFile(url: url)
            self.fileURL = url
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

    private func writeToFile(url: URL) {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            isEdited = false
        } catch {
            showError("Не удалось сохранить файл: \(error.localizedDescription)")
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
    let onClose: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Найти", text: $searchQuery)
                .textFieldStyle(.plain)
                .focused($isFocused)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            isFocused = true
        }
    }
}

private struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    var searchQuery: String
    var currentMatchIndex: Int
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

        textView.string = text
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }

        context.coordinator.applyHighlight(
            to: textView,
            searchQuery: searchQuery,
            currentMatchIndex: currentMatchIndex
        ) { count in
            DispatchQueue.main.async {
                onMatchesCountChange(count)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        func applyHighlight(
            to textView: NSTextView,
            searchQuery: String,
            currentMatchIndex: Int,
            countHandler: (Int) -> Void
        ) {
            guard let textStorage = textView.textStorage else { return }

            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.removeAttribute(.backgroundColor, range: fullRange)

            guard !searchQuery.isEmpty else {
                countHandler(0)
                return
            }

            let content = textStorage.string as NSString
            var ranges: [NSRange] = []
            var searchRange = NSRange(location: 0, length: content.length)

            while searchRange.location < content.length {
                let foundRange = content.range(of: searchQuery, options: .caseInsensitive, range: searchRange)
                if foundRange.location == NSNotFound { break }

                ranges.append(foundRange)

                let nextLocation = foundRange.location + foundRange.length
                searchRange = NSRange(location: nextLocation, length: content.length - nextLocation)
            }

            for (index, range) in ranges.enumerated() {
                let color: NSColor = index == currentMatchIndex
                    ? NSColor.orange
                    : NSColor.orange.withAlphaComponent(0.35)
                textStorage.addAttribute(.backgroundColor, value: color, range: range)
            }

            if ranges.indices.contains(currentMatchIndex) {
                textView.scrollRangeToVisible(ranges[currentMatchIndex])
            }

            countHandler(ranges.count)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var document: EditorDocument

    var body: some View {
        VStack(spacing: 0) {
            EditorTextView(
                text: $document.text,
                searchQuery: document.searchQuery,
                currentMatchIndex: document.currentMatchIndex,
                onMatchesCountChange: { count in
                    document.matchesCount = count
                }
            )

            if document.isSearchBarVisible {
                Divider()
                SearchBarView(searchQuery: $document.searchQuery) {
                    document.isSearchBarVisible = false
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
