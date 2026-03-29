import SwiftUI
import AppKit
import Carbon.HIToolbox
import ChitChatCore

/// A SwiftUI view that wraps an NSView for capturing global hotkey combinations.
/// When active, it listens for the next key press and records the key code + modifiers.
struct HotkeyRecorderView: View {
    @Binding var binding: HotkeyBinding
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 8) {
            Text(isRecording ? "Press a key combination..." : binding.displayString)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(isRecording ? .secondary : .primary)
                .frame(minWidth: 120)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )

            if isRecording {
                Button("Cancel") {
                    isRecording = false
                }
                .buttonStyle(.borderless)
                .font(.caption)
            } else {
                Button("Record") {
                    isRecording = true
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .background {
            if isRecording {
                KeyCaptureRepresentable { keyCode, modifiers in
                    let display = Self.displayString(keyCode: keyCode, modifiers: modifiers)
                    binding = HotkeyBinding(
                        keyCode: UInt32(keyCode),
                        modifiers: UInt32(modifiers),
                        displayString: display
                    )
                    isRecording = false
                }
                .frame(width: 0, height: 0)
            }
        }
    }

    // MARK: - Display String Builder

    static func displayString(keyCode: UInt16, modifiers: UInt) -> String {
        var parts: [String] = []

        if modifiers & NSEvent.ModifierFlags.control.rawValue != 0 { parts.append("\u{2303}") }
        if modifiers & NSEvent.ModifierFlags.option.rawValue != 0 { parts.append("\u{2325}") }
        if modifiers & NSEvent.ModifierFlags.shift.rawValue != 0 { parts.append("\u{21E7}") }
        if modifiers & NSEvent.ModifierFlags.command.rawValue != 0 { parts.append("\u{2318}") }

        parts.append(keyName(for: keyCode))
        return parts.joined()
    }

    static func keyName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_Escape: return "Esc"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_UpArrow: return "\u{2191}"
        case kVK_DownArrow: return "\u{2193}"
        case kVK_LeftArrow: return "\u{2190}"
        case kVK_RightArrow: return "\u{2192}"
        default:
            // Convert keyCode to character using the current keyboard layout
            let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
            guard let layoutDataRef else { return "Key\(keyCode)" }

            let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self)
            let layout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)

            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length: Int = 0

            UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )

            if length > 0 {
                return String(utf16CodeUnits: chars, count: length).uppercased()
            }
            return "Key\(keyCode)"
        }
    }
}

// MARK: - NSView Key Capture

/// NSViewRepresentable that becomes first responder and captures key events.
private struct KeyCaptureRepresentable: NSViewRepresentable {
    let onKeyCaptured: (UInt16, UInt) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyCaptured = onKeyCaptured
        // Become first responder on next run loop tick
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onKeyCaptured = onKeyCaptured
    }
}

private class KeyCaptureNSView: NSView {
    var onKeyCaptured: ((UInt16, UInt) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Require at least one modifier (except for function keys)
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
        let isFunctionKey = (Int(event.keyCode) >= kVK_F1 && Int(event.keyCode) <= kVK_F12)
            || Int(event.keyCode) == kVK_F13
            || Int(event.keyCode) == kVK_F14
            || Int(event.keyCode) == kVK_F15

        if modifiers != 0 || isFunctionKey {
            onKeyCaptured?(event.keyCode, modifiers)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        // Don't capture modifier-only presses
    }
}
