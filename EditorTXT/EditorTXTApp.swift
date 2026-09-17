import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Системная"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var document: EditorDocument?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let document, !document.confirmDiscardChanges() {
            return .terminateCancel
        }
        return .terminateNow
    }
}

@main
struct EditorTXTApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var document = EditorDocument()
    @AppStorage("appTheme") private var themeRawValue: String = AppTheme.system.rawValue

    private var currentTheme: AppTheme {
        AppTheme(rawValue: themeRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(document)
                .frame(minWidth: 500, minHeight: 400)
                .preferredColorScheme(currentTheme.colorScheme)
                .onAppear {
                    appDelegate.document = document
                }
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

            CommandGroup(after: .textEditing) {
                Divider()

                Button("Find...") {
                    document.isSearchBarVisible.toggle()
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            CommandMenu("View") {
                ForEach(AppTheme.allCases) { theme in
                    Button {
                        themeRawValue = theme.rawValue
                    } label: {
                        if theme == currentTheme {
                            Label(theme.title, systemImage: "checkmark")
                        } else {
                            Text(theme.title)
                        }
                    }
                }
            }
        }
    }
}
