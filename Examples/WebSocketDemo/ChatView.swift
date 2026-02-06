import SwiftUI

struct ChatView: View {
    @State private var viewModel = ChatViewModel()
    @State private var input = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status bar
                HStack {
                    Circle()
                        .fill(viewModel.isConnected ? .green : .red)
                        .frame(width: 10, height: 10)
                    Text(viewModel.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(viewModel.isConnected ? "Disconnect" : "Connect") {
                        if viewModel.isConnected {
                            viewModel.disconnect()
                        } else {
                            viewModel.connect()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(viewModel.isConnected ? .red : .green)
                }
                .padding()

                Divider()

                // Messages
                List(viewModel.messages) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.text)
                        Text("\(message.sender) - \(message.timestamp)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.plain)

                Divider()

                // Input
                HStack {
                    TextField("Type a message...", text: $input)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { sendMessage() }

                    Button("Send") { sendMessage() }
                        .buttonStyle(.borderedProminent)
                        .disabled(input.isEmpty || !viewModel.isConnected)
                }
                .padding()
            }
            .navigationTitle("WebSocket Demo")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func sendMessage() {
        let text = input
        input = ""
        viewModel.send(text)
    }
}

#Preview {
    ChatView()
}
