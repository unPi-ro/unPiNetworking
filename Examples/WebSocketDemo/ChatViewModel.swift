import Foundation
import unPiNetworking

@MainActor
@Observable
final class ChatViewModel {
    var messages: [ServerMessage] = []
    var isConnected = false
    var statusText = "Disconnected"

    private let webSocket = WebSocketService(
        configuration: WebSocketConfiguration(
            retryCount: 3,
            retryBaseDelay: 1.0,
            pingInterval: nil
        )
    )

    private var receiveTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?

    func connect() {
        watchConnectionState()

        receiveTask = Task {
            do {
                // Change to your Mac's IP if testing on a physical device
                try await webSocket.connect(
                    url: URL(string: "ws://localhost:8765")!,
                    headers: nil
                )

                let stream = await webSocket.receive(ServerMessage.self)

                for try await message in stream {
                    messages.append(message)
                }
            } catch {
                statusText = "Error: \(error.localizedDescription)"
            }
        }
    }

    func send(_ text: String) {
        guard !text.isEmpty else { return }
        Task {
            try await webSocket.send(ChatMessage(text: text, sender: "me"))
        }
    }

    func disconnect() {
        receiveTask?.cancel()
        Task { await webSocket.disconnect() }
    }

    private func watchConnectionState() {
        stateTask = Task {
            for await state in webSocket.connectionState {
                switch state {
                case .connected:
                    isConnected = true
                    statusText = "Connected"
                case .connecting:
                    isConnected = false
                    statusText = "Connecting..."
                case .reconnecting(let attempt, let max):
                    isConnected = false
                    statusText = "Reconnecting \(attempt)/\(max)..."
                case .disconnected:
                    isConnected = false
                    statusText = "Disconnected"
                }
            }
        }
    }
}
