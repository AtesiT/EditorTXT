import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var document: EditorDocument

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $document.text)
                .font(.system(size: 14, design: .monospaced))
                .padding(8)
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

#Preview {
    ContentView()
        .environmentObject(EditorDocument())
}
