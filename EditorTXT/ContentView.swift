import SwiftUI
import Combine
import UniformTypeIdentifiers

final class EditorDocument: ObservableObject {
    @Published var text: String = "" {
        didSet {
            guard !isLoading else { return }
            isEdited = true
        }
    }
    @Published var fileURL: URL?
    @Published var isEdited: Bool = false

    private var isLoading = false

    var displayName: String {
        fileURL?.lastPathComponent ?? "Untitled"
    }

    func newDocument() {
        isLoading = true
        text = ""
        fileURL = nil
        isEdited = false
        isLoading = false
    }

    func openFile() {
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

struct ContentView: View {
    @EnvironmentObject private var document: EditorDocument

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $document.text)
                .font(.system(size: 14, design: .monospaced))
                .padding(8)
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(
            WindowConfigurator(
                title: document.displayName,
                isEdited: document.isEdited,
                representedURL: document.fileURL
            )
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(EditorDocument())
}
