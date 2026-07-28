import SwiftUI

enum PageMessage: Equatable {
    case success(String)
    case error(String)

    var text: String {
        switch self {
        case let .success(text), let .error(text): text
        }
    }
}

struct MessageBar: View {
    let message: PageMessage

    var body: some View {
        Label(message.text, systemImage: symbol)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(color.opacity(0.09))
    }

    private var color: Color {
        switch message {
        case .success: .green
        case .error: .red
        }
    }

    private var symbol: String {
        switch message {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }
}
