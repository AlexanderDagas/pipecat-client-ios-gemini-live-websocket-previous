import Foundation
import PipecatClientIOS

protocol GeminiLiveWebSocketConnectionDelegate: AnyObject {
    func connectionDidFinishModelSetup(
        _: GeminiLiveWebSocketConnection
    )
    func connection(
        _: GeminiLiveWebSocketConnection,
        didReceiveModelAudioBytes audioBytes: Data
    )
    func connectionDidDetectUserInterruption(_: GeminiLiveWebSocketConnection)
}

class GeminiLiveWebSocketConnection: NSObject, URLSessionWebSocketDelegate {
    
    // MARK: - Public
    
    struct Options {
        let apiKey: String
        let initialMessages: [WebSocketMessages.Outbound.TextInput]
        let generationConfig: Value?
    }
    
    public weak var delegate: GeminiLiveWebSocketConnectionDelegate? = nil
    
    // Default initializer for compatibility with transport
    override init() {
        // We'll set options later via configure method
        self.options = nil
        super.init()
    }
    
    init(options: Options) {
        self.options = options
        super.init()
    }
    
    // Method to configure the connection after initialization
    func configure(apiKey: String, initialMessages: [WebSocketMessages.Outbound.TextInput] = [], generationConfig: Value? = nil) {
        self.options = Options(
            apiKey: apiKey,
            initialMessages: initialMessages,
            generationConfig: generationConfig
        )
    }
    
    func connect() async throws {
        print("🔍 DEBUG: GeminiLiveWebSocketConnection.connect() called")
        
        guard let options = options else {
            print("🔍 DEBUG: No options configured - throwing error")
            throw NSError(domain: "GeminiLiveWebSocketConnection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Connection not configured. Call configure() first."])
        }
        
        print("🔍 DEBUG: Options found - API key: \(options.apiKey.prefix(20))...")
        
        guard socket == nil else {
            print("🔍 DEBUG: Socket already exists - returning")
            assertionFailure()
            return
        }
        
        // Create web socket
        let urlSession = URLSession(
            configuration: .default,
            delegate: self,
            delegateQueue: OperationQueue()
        )
        
        // Use the official Gemini Live API WebSocket endpoint
        let urlString = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(options.apiKey)"
        print("🔍 DEBUG: Attempting to connect to URL: \(urlString.prefix(100))...")
        
        let url = URL(string: urlString)
        print("🔍 DEBUG: URL object created: \(url?.absoluteString.prefix(100) ?? "nil")...")
        
        let socket = urlSession.webSocketTask(with: url!)
        self.socket = socket
        
        print("🔍 DEBUG: WebSocket task created successfully")
        
        // Connect
        // NOTE: at this point no need to wait for socket to open to start sending events
        socket.resume()
        
        // Send initial setup message
        // Updated model to match the working fork
        let model = "models/gemini-2.5-flash-preview-native-audio-dialog"
        try await sendMessage(
            message: WebSocketMessages.Outbound.Setup(
                model: model,
                generationConfig: options.generationConfig
            )
        )
        try Task.checkCancellation()
        
        // Send initial context messages
        for message in options.initialMessages {
            try await sendMessage(message: message)
            try Task.checkCancellation()
        }
        
        // Listen for server messages
        Task {
            while true {
                do {
                    let decoder = JSONDecoder()
                    
                    let message = try await socket.receive()
                    try Task.checkCancellation()
                    
                    switch message {
                    case .data(let data):
                        print("📨 Received server message: \(String(data: data, encoding: .utf8)?.prefix(100) ?? "nil")")
                        
                        // Check for setup complete message
                        let setupCompleteMessage = try? decoder.decode(
                            WebSocketMessages.Inbound.SetupComplete.self,
                            from: data
                        )
                        if let setupCompleteMessage {
                            delegate?.connectionDidFinishModelSetup(self)
                            continue
                        }
                        
                        // Check for audio output message
                        let audioOutputMessage = try? decoder.decode(
                            WebSocketMessages.Inbound.AudioOutput.self,
                            from: data
                        )
                        if let audioOutputMessage, let audioBytes = audioOutputMessage.audioBytes() {
                            delegate?.connection(
                                self,
                                didReceiveModelAudioBytes: audioBytes
                            )
                        }
                        
                        // Check for interrupted message
                        let interruptedMessage = try? decoder.decode(
                            WebSocketMessages.Inbound.Interrupted.self,
                            from: data
                        )
                        if let interruptedMessage {
                            delegate?.connectionDidDetectUserInterruption(self)
                            continue
                        }
                        continue
                    case .string(let string):
                        Logger.shared.warn("Received server message of unexpected type: \(string)")
                        continue
                    }
                } catch {
                    print("❌ WebSocket receive error: \(error)")
                    // Socket is known to be closed (set to nil), so break out of the socket receive loop
                    if self.socket == nil {
                        break
                    }
                    // Otherwise wait a smidge and loop again
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
        }
        
        // We finished all the connect() steps
        didFinishConnect = true
    }
    
    func sendUserAudio(_ audio: Data) async throws {
        // Only send user audio once the connect() steps (which includes model setup) have finished
        if !didFinishConnect {
            return
        }
        try await sendMessage(
            message: WebSocketMessages.Outbound.AudioInput(audio: audio)
        )
    }
    
    func sendMessage(message: Encodable) async throws {
        let encoder = JSONEncoder()
        
        let messageString = try! String(
            data: encoder.encode(message),
            encoding: .utf8
        )!
        print("📤 Sending message: \(messageString.prefix(100))")
        try await socket?.send(.string(messageString))
    }
    
    func disconnect() {
        // This will trigger urlSession(_:webSocketTask:didCloseWith:reason:), where we will nil out socket and thus cause the socket receive loop to end
        socket?.cancel(with: .normalClosure, reason: nil)
    }
    
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        print("🔌 WebSocket opened successfully!")
    }
    
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        print("❌ WebSocket closed! Close code: \(closeCode), reason: \(reason != nil ? String(data: reason!, encoding: .utf8) ?? "nil" : "nil")")
        socket = nil
        didFinishConnect = false
    }
    
    // MARK: - Private
    
    private var options: GeminiLiveWebSocketConnection.Options?
    private var socket: URLSessionWebSocketTask?
    private var didFinishConnect = false
}
