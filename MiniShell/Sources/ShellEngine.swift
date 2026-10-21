import SwiftUI
import Combine

/// A tiny sandboxed shell with its own virtual file system,
/// persisted to the app's UserDefaults as JSON.
final class ShellEngine: ObservableObject {
    @Published var lines: [TerminalLine] = []
    @Published var cwd = "/"

    struct Node: Codable {
        var name: String
        var isDir: Bool
        var content: String = ""
        var children: [Node] = []
    }

    private var root = Node(name: "/", isDir: true)
    private let saveKey = "minishell.fs"
    private var saveTimer: AnyCancellable?

    // MARK: - Setup

    init() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let saved = try? JSONDecoder().decode(Node.self, from: data) {
            root = saved
        } else {
            seed()
        }
        saveTimer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { _ in self.persist() }
        banner()
    }

    private func seed() {
        root.children = [
            .init(name: "README.md", isDir: false, content: """
            Welcome to mini-shell!

            A tiny sandboxed terminal for iOS, in the spirit of a-Shell —
            but fully offline and no AI. Everything runs on-device in a
            virtual file system that lives inside the app.

            Try:
              help            list every command
              ls              look around
              touch notes.txt create a file
              echo hello > notes.txt
              cat notes.txt
              cowsay hi
            """),
            .init(name: "home", isDir: true, children: [.init(name: "guest", isDir: true)]),
            .init(name: "tmp", isDir: true),
        ]
        cwd = "/"
    }

    func banner() {
        var lb = LineBuilder()
        lb.add("mini-shell 1.0  ·  a sandboxed terminal", C.green); lb.nl()
        lb.add("type `help` for the command list", C.gray); lb.nl(); lb.nl()
        lines.append(lb.asLine())
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(root) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    // MARK: - Path helpers

    private func normalized(_ path: String) -> [String] {
        var comps = path == "/" || path.isEmpty
            ? [] : path.split(separator: "/").map(String.init)
        if path.hasPrefix("/") { return resolve(comps) }
        var cur = cwd == "/" ? [] : cwd.split(separator: "/").map(String.init)
        for c in comps {
            if c == "." { continue }
            if c == ".." { _ = cur.popLast() }
            else { cur.append(c) }
        }
        return cur
    }
    private func resolve(_ comps: [String]) -> [String] { comps }

    private func node(at comps: [String]) -> Node? {
        var cur = root
        for c in comps {
            guard let i = cur.children.firstIndex(where: { $0.name == c }) else { return nil }
            cur = cur.children[i]
        }
        return cur
    }

    private func parent(of comps: [String]) -> (Node, String)? {
        guard var cur = node(at: Array(comps.dropLast())) else { return nil }
        guard cur.isDir else { return nil }
        return (cur, comps.last ?? "")
    }

    // MARK: - Execution

    func execute(_ raw: String) {
        var lb = LineBuilder()
        lb.add("❯ ", C.green)
        lb.add(raw, C.white)
        lines.append(lb.asLine(isCommand: true))

        let redirects = raw.contains(">")
        var cmdLine = raw
        var outFile: String? = nil
        if redirects {
            let parts = raw.components(separatedBy: " ")
            if let i = parts.firstIndex(of: ">") {
                cmdLine = parts[..<i].joined(separator: " ")
                outFile = parts.dropFirst(i + 1).joined(separator: " ")
            }
        }

        let words = cmdLine.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let command = words.first else { return }
        let args = Array(words.dropFirst())

        let output: [(String, Color)] = run(command, args)

        if let file = outFile {
            writeToFile(output.map(\.0).joined(), to: file)
        } else {
            var lb = LineBuilder()
            for (t, c) in output { lb.add(t, c) }
            if !output.isEmpty { lb.nl() }
            lines.append(lb.asLine())
        }
        persist()
    }

    private func writeToFile(_ text: String, to path: String) {
        let comps = normalized(path)
        guard comps.count > 0, let (par, name) = parent(of: comps) else { return }
        if let i = par.children.firstIndex(where: { $0.name == name }) {
            par.children[i].content = text
        } else {
            par.children.append(.init(name: name, isDir: false, content: text))
        }
    }

    // MARK: - Commands

    private func run(_ cmd: String, _ args: [String]) -> [(String, Color)] {
        switch cmd {
        case "help":
            return helpText
        case "ls":
            var comps = cwd == "/" ? [] : cwd.split(separator: "/").map(String.init)
            if args.count > 1 { comps = normalized(args[1]) }
            guard let n = node(at: comps) else { return [("ls: no such path", C.red)] }
            if !n.isDir { return [(n.name, C.white)] }
            if n.children.isEmpty { return [("(empty)", C.gray)] }
            return n.children.sorted { $0.name < $1.name }
                .map { ($0.isDir ? $0.name + "/" : $0.name, $0.isDir ? C.blue : C.white) }
        case "cd":
            if args.isEmpty || args[0] == "/" { cwd = "/"; return [] }
            let comps = normalized(args[0])
            guard let n = node(at: comps), n.isDir else { return [("cd: not a directory", C.red)] }
            cwd = "/" + comps.joined(separator: "/")
            return []
        case "pwd":
            return [(cwd, C.white)]
        case "cat":
            guard args.count == 1, let n = node(at: normalized(args[0])) else { return [("cat: usage: cat <file>", C.red)] }
            if n.isDir { return [("cat: is a directory", C.red)] }
            return [(n.content.isEmpty ? "(empty file)" : n.content, C.white)]
        case "echo":
            return [(args.joined(separator: " "), C.white)]
        case "touch":
            guard let (par, name) = parent(of: normalized(args.first ?? "")) else { return [("touch: bad path", C.red)] }
            if !par.children.contains(where: { $0.name == name }) {
                par.children.append(.init(name: name, isDir: false))
            }
            return []
        case "mkdir":
            guard let (par, name) = parent(of: normalized(args.first ?? "")) else { return [("mkdir: bad path", C.red)] }
            par.children.append(.init(name: name, isDir: true))
            return []
        case "rm":
            guard let (par, name) = parent(of: normalized(args.first ?? "")) else { return [("rm: bad path", C.red)] }
            par.children.removeAll { $0.name == name }
            return []
        case "write":
            // write <file> <text...>
            guard args.count >= 2, let (par, name) = parent(of: normalized(args[0])) else { return [("write: usage: write <file> <text>", C.red)] }
            let text = args.dropFirst().joined(separator: " ")
            if let i = par.children.firstIndex(where: { $0.name == name }) {
                par.children[i].content = text
            } else {
                par.children.append(.init(name: name, isDir: false, content: text))
            }
            return []
        case "clear":
            DispatchQueue.main.async { self.lines = [] }
            return []
        case "date":
            return [(DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .medium), C.white)]
        case "whoami":
            return [("guest", C.yellow)]
        case "uname":
            return [("MiniShell 1.0 (sandbox) — \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)", C.white)]
        case "cowsay":
            let msg = args.joined(separator: " ")
            let bar = String(repeating: "_", count: msg.count + 2)
            let und = String(repeating: "-", count: msg.count + 2)
            return [("""
             \(bar)
            < \(msg) >
             \(und)
                    \\   ^__^
                     \\  (oo)\\_______
                        (__)\\       )\\/\\
                            ||----w |
                            ||     ||
            """, C.yellow)]
        case "history":
            let past = lines.filter(\.isCommand).compactMap { $0.spans.dropFirst().map(\.text).joined() }
            guard !past.isEmpty else { return [("(no history yet)", C.gray)] }
            return past.enumerated().map { ("\($0.offset + 1)  \($0.element)", C.white) }
        case "uptime":
            let secs = Int(ProcessInfo.processInfo.systemUptime)
            return [("up \(secs/3600)h \(secs%3600/60)m \(secs%60)s", C.white)]
        case "neofetch":
            return [("mini-shell 1.0\non-device sandbox\nno AI, no network\npure Swift + SwiftUI", C.green)]
        default:
            return [("\(cmd): command not found — try `help`", C.red)]
        }
    }

    private var helpText: [(String, Color)] {
        [("""
Available commands:
  help          this list
  ls [path]     list directory
  cd <path>     change directory
  pwd           print working directory
  cat <file>    print file
  echo <text>   print text (use `>` to redirect)
  touch <file>  create empty file
  write <f> t   write text to file
  mkdir <dir>   create directory
  rm <file>     remove file or dir
  clear         clear screen
  date, whoami, uname, uptime, history
  cowsay <msg>  say it with a cow
  neofetch      system info
""", C.green)]
    }
}
