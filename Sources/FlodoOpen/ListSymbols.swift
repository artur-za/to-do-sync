import SwiftUI
import FlowCore

struct ListSymbolChoice: Identifiable {
    let symbol: String
    let name: String
    var id: String { symbol }
    static let all: [Self] = [
        .init(symbol: "briefcase", name: "Work"), .init(symbol: "house", name: "Home"),
        .init(symbol: "book.closed", name: "Reading"), .init(symbol: "graduationcap", name: "Study"),
        .init(symbol: "desktopcomputer", name: "Computer"), .init(symbol: "chevron.left.forwardslash.chevron.right", name: "Code"),
        .init(symbol: "paintbrush", name: "Design"), .init(symbol: "lightbulb", name: "Ideas"),
        .init(symbol: "bolt", name: "Focus"), .init(symbol: "heart", name: "Personal"),
        .init(symbol: "cross.case", name: "Health"), .init(symbol: "dumbbell", name: "Fitness"),
        .init(symbol: "figure.run", name: "Running"), .init(symbol: "fork.knife", name: "Food"),
        .init(symbol: "cart", name: "Shopping"), .init(symbol: "creditcard", name: "Payments"),
        .init(symbol: "banknote", name: "Finance"), .init(symbol: "airplane", name: "Travel"),
        .init(symbol: "car", name: "Car"), .init(symbol: "globe", name: "Languages"),
        .init(symbol: "person.2", name: "Family"), .init(symbol: "person", name: "Self"),
        .init(symbol: "cup.and.saucer", name: "Breaks"), .init(symbol: "music.note", name: "Music"),
        .init(symbol: "camera", name: "Photography"), .init(symbol: "film", name: "Video"),
        .init(symbol: "gamecontroller", name: "Games"), .init(symbol: "wrench.and.screwdriver", name: "Repairs"),
        .init(symbol: "leaf", name: "Nature"), .init(symbol: "target", name: "Goals")
    ]
}

struct ListGlyph: View {
    let list: TaskList
    var size: CGFloat = 10
    var selected = false
    var body: some View {
        Group {
            if list.icon == nil || list.icon == "square" {
                RoundedRectangle(cornerRadius: size * 0.3)
                    .fill(selected ? Color(hex: list.color) : .clear)
                    .overlay(RoundedRectangle(cornerRadius: size * 0.3).strokeBorder(Color(hex: list.color), lineWidth: size > 12 ? 2 : 1.7))
            } else {
                Image(systemName: list.symbolName).font(.system(size: size + 1, weight: .semibold)).foregroundStyle(Color(hex: list.color))
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct DragDestination: Equatable {
    let bucket: Bucket
    let before: UUID?
}
