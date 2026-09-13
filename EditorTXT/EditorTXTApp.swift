import SwiftUI
import Combine
import UniformTypeIdentifiers

final class EditorDocument: ObservableObject {
    @Published var text: String = ""
    @Published var fileURL: URL?

    func newDocument() {
        text = ""
        fileURL = nil
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
                self.text = content
                self.fileURL = url
            } catch {
                showError("Не удалось открыть файл: \(error.localizedDescription)")
            }
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
    
    func saveFile() {
        if let url = fileURL {
            writeToFile(url: url)
        } else {
            saveFileAs()
        }
    }

    private func writeToFile(url: URL) {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
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

@main
struct EditorTXTApp: App {
    @StateObject private var document = EditorDocument()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(document)
                .frame(minWidth: 500, minHeight: 400)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") {
                    document.newDocument()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open...") {
                    document.openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .saveItem) {
                Button("Save") {
                    document.saveFile()
                }
                .keyboardShortcut("s", modifiers: .command)
                Button("Save As...") {
                    document.saveFileAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}
