import SwiftUI

struct ContentView: View {
    // Хранит текущий текст, отображаемый в редакторе
    @State private var text: String = ""

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $text)
                .font(.system(size: 14, design: .monospaced))
                .padding(8)
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

#Preview {
    ContentView()
}
