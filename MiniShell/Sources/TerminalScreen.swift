import SwiftUI

struct TerminalLine: Identifiable, Equatable {
    let id = UUID()
    var spans: [Span]          // colored pieces of one line
    var isCommand = false

    struct Span: Equatable {
        var text: String
        var color: Color = .green
    }
}

struct TerminalScreen: View {
    @StateObject private var shell = ShellEngine()
    @State private var input = ""
    @State private var history: [String] = []
    @State private var historyIndex: Int? = nil
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // status bar
            HStack {
                Text("mini-shell")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.accentColor)
                Spacer()
                Text(cwdLabel)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(white: 0.08))

            // scrollable terminal output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(shell.lines) { line in
                            Text(render(line))
                                .font(.system(size: 14, weight: .regular, design: .monospaced))
                                .lineSpacing(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                        promptRow
                    }
                    .padding(12)
                }
                .background(Color.black)
                .onChange(of: shell.lines.count) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            // input bar
            HStack(spacing: 8) {
                Text("❯")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.green)
                TextField("", text: $input)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focused)
                    .onSubmit(run)
                Button {
                    run()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(white: 0.08))
        }
        .background(Color.black.ignoresSafeArea())
        .onTapGesture { focused = true }
        .onAppear { shell.banner(); focused = true }
    }

    private var cwdLabel: String {
        let comps = shell.cwd.split(separator: "/").map(String.init)
        return comps.isEmpty ? "/" : "/" + comps.last!
    }

    private var promptRow: some View {
        Color.clear.frame(height: 1).id("bottom")
    }

    private func render(_ line: TerminalLine) -> AttributedString {
        var out = AttributedString()
        for span in line.spans {
            var piece = AttributedString(span.text)
            piece.foregroundColor = span.color
            out += piece
        }
        return out
    }

    private func run() {
        let cmd = input.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        history.append(cmd)
        historyIndex = nil
        input = ""
        shell.execute(cmd)
    }
}
