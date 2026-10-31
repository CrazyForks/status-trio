import Foundation

/// One item in the provisional power info bar: a label and its own reading.
/// Items are independent rails; they are never added together to claim a
/// whole-machine total.
struct PowerInfoBarItem: Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let title: LocalizationKey
    let value: String
}

/// The single-line power info bar under the panel's battery module. Missing or
/// stale rails are absent from `items`; the bar hides entirely when empty.
struct PowerInfoBarState: Equatable, Hashable, Sendable {
    let items: [PowerInfoBarItem]

    var isEmpty: Bool { items.isEmpty }
}
