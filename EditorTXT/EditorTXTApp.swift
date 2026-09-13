import SwiftUI
import Combine

final class EditorDocument: ObservableObject {
    @Published var text: String = ""

    func newDocument() {
        text = ""
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
            }
        }
    }
}
