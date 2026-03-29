import SwiftUI

enum PermissionStatus {
    case granted
    case denied
    case notDetermined

    var color: Color {
        switch self {
        case .granted: return .green
        case .denied: return .red
        case .notDetermined: return .yellow
        }
    }

    var icon: String {
        switch self {
        case .granted: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .notDetermined: return "questionmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .granted: return "Granted"
        case .denied: return "Not Granted"
        case .notDetermined: return "Not Determined"
        }
    }
}

struct PermissionStatusBadge: View {
    let status: PermissionStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
                .font(.caption)
            Text(status.label)
                .font(.caption)
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(status.color.opacity(0.1), in: Capsule())
    }
}
