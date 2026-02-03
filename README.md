# unPiNetworking

A lightweight, actor-based, protocol-driven networking layer for iOS.

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
