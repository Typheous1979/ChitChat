import Foundation

public struct HotkeyBinding: Codable, Sendable, Equatable {
    public let keyCode: UInt32
    public let modifiers: UInt32
    public let displayString: String

    public init(keyCode: UInt32, modifiers: UInt32, displayString: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayString = displayString
    }

    /// Default: Control + Shift + Space
    /// 0x40000 = NSEvent.ModifierFlags.control, 0x20000 = .shift
    public static let defaultBinding = HotkeyBinding(
        keyCode: 49,
        modifiers: 0x60000,
        displayString: "\u{2303}\u{21E7}Space"
    )
}
