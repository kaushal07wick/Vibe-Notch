import SwiftUI

/// Placeholder notch card. Real event cards (approve/deny, notifications) land next.
struct NotchView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
            Text("Vibe Notch")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(.white)
    }
}
