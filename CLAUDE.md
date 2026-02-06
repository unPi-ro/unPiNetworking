# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

unPiNetworking is a Swift Package Manager library providing a lightweight, protocol-based networking layer (HTTP and WebSocket) for iOS 17+. It uses Swift 6.1 with strict concurrency and has zero external dependencies.

## Build & Test Commands

```bash
swift build                  # Build the library
swift test                   # Run all tests
swift test --filter URLSessionTests/test_successfulRequest_returnsExpectedData  # Run a single test
swiftlint lint --strict      # Lint all Swift files (runs automatically on pre-push)
```

## Setup

Run `./bootstrap.sh` after cloning to install the pre-push git hook that enforces SwiftLint in strict mode. SwiftLint must be installed via `brew install swiftlint`.

## Architecture

### Core Types

- **`NetworkServiceProtocol`** (`unPiNetworking.swift`) - Public protocol defining the API surface. Two generic `request` methods: one for GET-style requests, one accepting an `Encodable` body.
- **`NetworkService`** (`unPiNetworking.swift`) - Actor implementing `NetworkServiceProtocol`. Handles header merging (config defaults + endpoint-specific, endpoint wins), automatic retry for transient `URLError` codes (timeout, connection lost, not connected), and JSON decoding.
- **`Endpoint`** (`Request.swift`) - Request builder struct. Holds path, method, query items, headers, body, base URL, and cache policy. Converts to `URLRequest` via `asURLRequest()`.
- **`NetworkConfiguration`** (`NetworkConfiguration.swift`) - Immutable config struct passed to `NetworkService` init. Controls default headers, timeout, retry count, cache policy, and content type. Produces `URLSessionConfiguration` via `makeURLSessionConfiguration()`.
- **`NetworkError`** (`NetworkError.swift`) - Error enum with cases for URL/request/response validation, HTTP status errors (includes status code and response data), decoding, cancellation, and timeout.
- **`HTTPMethod`** (`HTTPMethod.swift`) - Enum for GET, POST, PUT, DELETE, PATCH.

### WebSocket Types

- **`WebSocketServiceProtocol`** (`WebSocketService.swift`) - Public protocol defining the WebSocket API surface: connect, disconnect, send, receive, and connection state observation.
- **`WebSocketService`** (`WebSocketService.swift`) - Actor implementing `WebSocketServiceProtocol`. Handles header merging, auto-reconnect with exponential backoff + jitter, ping keep-alive, and `AsyncThrowingStream`-based message delivery with fan-out to multiple consumers.
- **`WebSocketConnectionState`** (`WebSocketService.swift`) - Enum for disconnected, connecting, connected, reconnecting(attempt, maxAttempts).
- **`WebSocketConfiguration`** (`WebSocketConfiguration.swift`) - Immutable config struct controlling default headers, timeout, retry count/delays, ping interval, and max message size.
- **`WebSocketError`** (`WebSocketError.swift`) - Error enum with cases for connection, send, receive, encoding/decoding failures, and reconnect exhaustion.
- **`URLSessionWebSocketTaskProtocol`** / **`WebSocketTaskProviding`** (`WebSocketTaskProviding.swift`) - Testability protocols abstracting `URLSessionWebSocketTask`. Production uses real `URLSession`; tests inject `MockWebSocketTask`.

### Data Flow

#### HTTP

`Client` -> `NetworkService.request(endpoint:)` -> merges config headers with endpoint headers -> `Endpoint.asURLRequest()` -> `URLSession.data(for:)` -> validates HTTP status (200-299) -> `JSONDecoder.decode(T.self)` -> returns `T` or retries/throws.

#### WebSocket

`Client` -> `WebSocketService.connect(url:headers:)` -> merges config headers with connect-time headers -> `WebSocketTaskProviding.createWebSocketTask(with:)` -> `task.resume()` -> receive loop distributes messages to `AsyncThrowingStream` continuations -> `JSONDecoder.decode(T.self)` -> typed stream to consumer. On error: auto-reconnect with exponential backoff.

### Concurrency Model

All public types conform to `Sendable`. `NetworkService` and `WebSocketService` are `actor`s for thread safety. All request/send methods are `async throws`. WebSocket message delivery uses `AsyncThrowingStream` with fan-out to multiple consumers.

### Testing Pattern

Tests use `URLProtocolStub` (a custom `URLProtocol` subclass) to intercept HTTP calls without hitting the network. The stub is registered on an ephemeral `URLSessionConfiguration`. WebSocket tests use `MockWebSocketTask` and `MockWebSocketTaskProvider` injected via the `taskProvider` init parameter, using `CheckedContinuation` to simulate received messages and errors. All tests follow Given/When/Then structure.

## SwiftLint Rules

Key thresholds configured in `.swiftlint.yml`:
- Line length: 150 warning, 200 error (ignores function declarations, comments, URLs)
- Identifier names: min 3 chars, max 70 (`id` and `qa` are excluded from minimum)
- Nesting: max 3 type levels
- `trailing_whitespace` is disabled
