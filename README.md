# unPiNetworking

A lightweight, actor-based, protocol-driven networking layer for iOS — HTTP and WebSocket.

## Requirements

- iOS 17+
- Swift 6.1
- No external dependencies

## Installation

Add unPiNetworking to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/unPi-ro/unPiNetworking.git", from: "1.0.0")
]
```

Then add it to your target:

```swift
.target(
    name: "YourApp",
    dependencies: ["unPiNetworking"]
)
```

## Usage

### Configuration

```swift
import unPiNetworking

let configuration = NetworkConfiguration(
    defaultHeaders: ["Authorization": "Bearer token"],
    timeoutInterval: 30,
    retryCount: 3,
    cachePolicy: .useProtocolCachePolicy,
    defaultContentType: "application/json"
)

let service = NetworkService(configuration: configuration)
```

All configuration parameters have defaults, so the simplest setup is:

```swift
let service = NetworkService(configuration: NetworkConfiguration())
```

### GET Request

```swift
struct User: Decodable, Sendable {
    let id: Int
    let name: String
}

let endpoint = Endpoint(
    baseURL: URL(string: "https://api.example.com")!,
    path: "/users/1"
)

let user: User = try await service.request(endpoint)
```

### GET Request with Query Parameters

```swift
let endpoint = Endpoint(
    baseURL: URL(string: "https://api.example.com")!,
    path: "/users",
    queryItems: [URLQueryItem(name: "page", value: "1")]
)

let users: [User] = try await service.request(endpoint)
```

### POST Request with Body

```swift
struct CreateUser: Encodable, Sendable {
    let name: String
    let email: String
}

let endpoint = Endpoint(
    baseURL: URL(string: "https://api.example.com")!,
    path: "/users",
    method: .post
)

let newUser = CreateUser(name: "Ada", email: "ada@example.com")
let created: User = try await service.request(endpoint, body: newUser)
```

### Error Handling

`NetworkService` throws `NetworkError` for URL, response, and HTTP status failures. Other errors (decoding, URL session) are rethrown as-is.

```swift
do {
    let user: User = try await service.request(endpoint)
} catch let error as NetworkError {
    switch error {
    case .invalidURL:
        print("Invalid URL")
    case .invalidResponse:
        print("Invalid response")
    case .httpError(let statusCode, let data):
        print("HTTP \(statusCode): \(String(data: data, encoding: .utf8) ?? "")")
    default:
        print("Network error: \(error)")
    }
} catch is DecodingError {
    print("Failed to decode response")
} catch let error as URLError {
    print("URL error: \(error.code)")
} catch {
    print("Unexpected error: \(error)")
}
```

### Custom Headers per Request

Endpoint headers are merged with configuration defaults. Endpoint headers take priority on conflicts.

```swift
let endpoint = Endpoint(
    baseURL: URL(string: "https://api.example.com")!,
    path: "/users",
    headers: ["X-Custom-Header": "value"]
)
```

### Automatic Retry

`NetworkService` automatically retries requests that fail with transient `URLError` codes (timeout, connection lost, not connected to internet). The retry count is configured via `NetworkConfiguration.retryCount` (default: 3).

## WebSocket

### Configuration

```swift
let config = WebSocketConfiguration(
    defaultHeaders: ["Authorization": "Bearer token"],
    timeoutInterval: 30,        // Handshake timeout
    retryCount: 3,              // Auto-reconnect attempts
    retryBaseDelay: 1.0,        // Initial backoff delay (doubles each retry)
    retryMaxDelay: 30.0,        // Maximum backoff delay
    pingInterval: 30.0,         // Keep-alive ping interval (nil to disable)
    maximumMessageSize: 1_048_576  // 1 MB max message size
)

let service = WebSocketService(configuration: config)
```

All parameters have defaults, so the simplest setup is:

```swift
let service = WebSocketService()
```

### Connect and Disconnect

```swift
// Connect with optional per-connection headers
try await service.connect(
    url: URL(string: "wss://example.com/ws")!,
    headers: ["X-Room-Id": "123"]
)

// Disconnect (defaults to .normalClosure)
await service.disconnect()

// Disconnect with a specific close code
await service.disconnect(closeCode: .goingAway, reason: nil)
```

Header merging works the same as HTTP — config defaults + connect-time headers, connect-time wins on conflicts.

### Send Messages

```swift
struct ChatMessage: Codable, Sendable {
    let text: String
    let sender: String
}

try await service.send(ChatMessage(text: "Hello!", sender: "me"))
```

### Receive Messages

`receive` returns a typed `AsyncThrowingStream` — iterate with `for try await`:

```swift
struct ServerMessage: Codable, Sendable {
    let text: String
    let sender: String
    let timestamp: String
}

let stream = await service.receive(ServerMessage.self)

for try await message in stream {
    print("\(message.sender): \(message.text)")
}
```

Multiple consumers can call `receive` — each gets all messages (fan-out).

### Connection State

Observe connection state changes via `AsyncStream`:

```swift
for await state in service.connectionState {
    switch state {
    case .disconnected:
        print("Disconnected")
    case .connecting:
        print("Connecting...")
    case .connected:
        print("Connected")
    case .reconnecting(let attempt, let maxAttempts):
        print("Reconnecting \(attempt)/\(maxAttempts)...")
    }
}
```

Or check the current state directly:

```swift
let state = await service.currentState
```

### Auto-Reconnect

On unexpected disconnection, `WebSocketService` automatically reconnects with exponential backoff plus jitter. After exhausting all retry attempts, the state becomes `.disconnected`. Intentional disconnects (calling `disconnect()`) do not trigger reconnection.

### Error Handling

WebSocket operations throw `WebSocketError`:

```swift
do {
    try await service.send(message)
} catch let error as WebSocketError {
    switch error {
    case .notConnected:
        print("Not connected")
    case .encodingError(let error):
        print("Failed to encode: \(error)")
    case .sendFailed(let error):
        print("Send failed: \(error)")
    case .maxReconnectAttemptsExhausted:
        print("Gave up reconnecting")
    default:
        print("WebSocket error: \(error)")
    }
}
```

### Demo App

A demo iOS app and a Python echo server are included in `Examples/`:

```bash
# Terminal 1 — start the echo server
pip3 install websockets
python3 Examples/echo_server.py

# Xcode — open and run the demo app on Simulator
open Examples/WebSocketDemo/WebSocketDemo.xcodeproj
```

## Development

```bash
git clone https://github.com/unPi-ro/unPiNetworking.git
cd unPiNetworking
./bootstrap.sh          # Install pre-push git hook
swift build             # Build
swift test              # Run all tests
swiftlint lint --strict # Lint
```

## License

MIT
