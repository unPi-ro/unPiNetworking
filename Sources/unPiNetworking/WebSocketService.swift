import Foundation

@available(iOS 15.0, macOS 10.15, *)
public enum WebSocketConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int, maxAttempts: Int)
}

@available(iOS 15.0, macOS 10.15, *)
public protocol WebSocketServiceProtocol: Sendable {
    func connect(url: URL, headers: [String: String]?) async throws
    func disconnect(closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) async
    func send<T: Encodable & Sendable>(_ message: T) async throws
    func receive<T: Decodable & Sendable>(_ type: T.Type) async -> AsyncThrowingStream<T, Error>
    var connectionState: AsyncStream<WebSocketConnectionState> { get }
    var currentState: WebSocketConnectionState { get async }
}

@available(iOS 15.0, macOS 10.15, *)
extension WebSocketServiceProtocol {
    public func disconnect() async {
        await disconnect(closeCode: .normalClosure, reason: nil)
    }
}

@available(iOS 15.0, macOS 10.15, *)
public actor WebSocketService: WebSocketServiceProtocol {
    private let configuration: WebSocketConfiguration
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let taskProvider: WebSocketTaskProviding

    private var webSocketTask: URLSessionWebSocketTaskProtocol?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var intentionalDisconnect = false
    private var currentURL: URL?
    private var currentHeaders: [String: String]?

    private var messageContinuations: [UUID: AsyncThrowingStream<URLSessionWebSocketTask.Message, Error>.Continuation] = [:]

    private var _currentState: WebSocketConnectionState = .disconnected
    public nonisolated let connectionState: AsyncStream<WebSocketConnectionState>
    private let stateContinuation: AsyncStream<WebSocketConnectionState>.Continuation

    public var currentState: WebSocketConnectionState {
        _currentState
    }

    public init(
        configuration: WebSocketConfiguration = WebSocketConfiguration(),
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        taskProvider: WebSocketTaskProviding? = nil
    ) {
        self.configuration = configuration
        self.encoder = encoder
        self.decoder = decoder
        self.taskProvider = taskProvider ?? URLSessionWebSocketTaskProvider(
            timeoutInterval: configuration.timeoutInterval
        )
        let (stream, continuation) = AsyncStream.makeStream(of: WebSocketConnectionState.self)
        self.connectionState = stream
        self.stateContinuation = continuation
    }

    deinit {
        stateContinuation.finish()
    }

    public func connect(url: URL, headers: [String: String]? = nil) async throws {
        intentionalDisconnect = false
        currentURL = url
        currentHeaders = headers

        updateState(.connecting)

        var request = URLRequest(url: url)
        request.timeoutInterval = configuration.timeoutInterval

        var mergedHeaders = configuration.defaultHeaders
        if let headers {
            mergedHeaders.merge(headers) { _, new in new }
        }
        for (key, value) in mergedHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let task = taskProvider.createWebSocketTask(with: request)
        task.resume()
        self.webSocketTask = task

        updateState(.connected)
        startReceiveLoop()
        startPingIfNeeded()
    }

    public func disconnect(closeCode: URLSessionWebSocketTask.CloseCode = .normalClosure, reason: Data? = nil) async {
        intentionalDisconnect = true
        stopReceiveLoop()
        stopPing()

        webSocketTask?.cancel(with: closeCode, reason: reason)
        webSocketTask = nil

        finishAllContinuations()
        updateState(.disconnected)
    }

    public func send<T: Encodable & Sendable>(_ message: T) async throws {
        guard let task = webSocketTask else {
            throw WebSocketError.notConnected
        }

        let data: Data
        do {
            data = try encoder.encode(message)
        } catch {
            throw WebSocketError.encodingError(error)
        }

        do {
            try await task.send(.data(data))
        } catch {
            throw WebSocketError.sendFailed(error)
        }
    }

    public func receive<T: Decodable & Sendable>(_ type: T.Type) -> AsyncThrowingStream<T, Error> {
        let continuationID = UUID()
        let decoder = self.decoder

        let (rawStream, rawContinuation) = AsyncThrowingStream.makeStream(
            of: URLSessionWebSocketTask.Message.self
        )
        messageContinuations[continuationID] = rawContinuation

        rawContinuation.onTermination = { @Sendable [weak self] _ in
            guard let self else { return }
            Task {
                await self.removeContinuation(continuationID)
            }
        }

        return AsyncThrowingStream<T, Error> { continuation in
            let task = Task {
                do {
                    for try await rawMessage in rawStream {
                        let data: Data
                        switch rawMessage {
                        case .data(let messageData):
                            data = messageData
                        case .string(let string):
                            guard let stringData = string.data(using: .utf8) else {
                                continuation.finish(throwing: WebSocketError.decodingError(
                                    DecodingError.dataCorrupted(
                                        DecodingError.Context(
                                            codingPath: [],
                                            debugDescription: "Failed to convert string to UTF-8 data"
                                        )
                                    )
                                ))
                                return
                            }
                            data = stringData
                        @unknown default:
                            continue
                        }

                        do {
                            let decoded = try decoder.decode(T.self, from: data)
                            continuation.yield(decoded)
                        } catch {
                            continuation.finish(throwing: WebSocketError.decodingError(error))
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Private

    private func updateState(_ state: WebSocketConnectionState) {
        _currentState = state
        stateContinuation.yield(state)
    }

    private func removeContinuation(_ identifier: UUID) {
        messageContinuations.removeValue(forKey: identifier)
    }

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop()
        }
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            guard let task = webSocketTask else { break }

            do {
                let message = try await task.receive()
                for continuation in messageContinuations.values {
                    continuation.yield(message)
                }
            } catch {
                if !intentionalDisconnect {
                    for continuation in messageContinuations.values {
                        continuation.finish(throwing: WebSocketError.receiveFailed(error))
                    }
                    messageContinuations.removeAll()
                    await attemptReconnect()
                }
                break
            }
        }
    }

    private func stopReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = nil
    }

    private func startPingIfNeeded() {
        guard let interval = configuration.pingInterval else { return }

        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                guard let self else { break }
                await self.sendPing()
            }
        }
    }

    private func sendPing() {
        webSocketTask?.sendPing { _ in }
    }

    private func stopPing() {
        pingTask?.cancel()
        pingTask = nil
    }

    private func attemptReconnect() async {
        guard !intentionalDisconnect,
              let url = currentURL else {
            updateState(.disconnected)
            return
        }

        stopReceiveLoop()
        stopPing()
        webSocketTask = nil

        for attempt in 1...configuration.retryCount {
            updateState(.reconnecting(attempt: attempt, maxAttempts: configuration.retryCount))

            let jitter = Double.random(in: 0...0.5)
            let delay = min(
                configuration.retryMaxDelay,
                configuration.retryBaseDelay * pow(2.0, Double(attempt - 1)) + jitter
            )

            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard !intentionalDisconnect else {
                updateState(.disconnected)
                return
            }

            do {
                try await connect(url: url, headers: currentHeaders)
                return
            } catch {
                continue
            }
        }

        updateState(.disconnected)
    }

    private func finishAllContinuations() {
        for continuation in messageContinuations.values {
            continuation.finish()
        }
        messageContinuations.removeAll()
    }
}
