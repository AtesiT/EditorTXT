import SwiftUI

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
