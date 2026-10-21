import SwiftUI

enum C {
    static let green = Color(red: 0.2, green: 0.95, blue: 0.3)
    static let white = Color(white: 0.92)
    static let gray  = Color(white: 0.55)
    static let yellow = Color(red: 1.0, green: 0.8, blue: 0.2)
    static let red   = Color(red: 1.0, green: 0.35, blue: 0.3)
    static let blue  = Color(red: 0.4, green: 0.7, blue: 1.0)
}

/// Builds colored terminal lines with a tiny builder API.
struct LineBuilder {
    var spans: [TerminalLine.Span] = []

    mutating func add(_ text: String, _ color: Color) {
        for (i, chunk) in text.components(separatedBy: "\n").enumerated() {
            if i > 0 { spans.append(.init(text: "\n", color: color)) }
            spans.append(.init(text: chunk, color: color))
        }
    }
    mutating func nl() { spans.append(.init(text: "\n", color: C.white)) }
    func asLine(isCommand: Bool = false) -> TerminalLine {
        .init(spans: spans, isCommand: isCommand)
    }
}
