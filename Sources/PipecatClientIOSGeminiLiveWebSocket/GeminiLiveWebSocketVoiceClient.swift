import Foundation
import PipecatClientIOS

@MainActor
public class GeminiLiveWebSocketVoiceClient {
    private let pipecatClient: PipecatClient
    private let transport: GeminiLiveWebSocketTransport
    
    internal init(apiKey: String, initialMessages: [WebSocketMessages.Outbound.TextInput] = [], generationConfig: Value? = nil) {
        // Create transport
        self.transport = GeminiLiveWebSocketTransport()
        
        // Configure transport with API key
        self.transport.configure(
            apiKey: apiKey,
            initialMessages: initialMessages,
            generationConfig: generationConfig
        )
        
        // Create PipecatClient with transport
        self.pipecatClient = PipecatClient(options: PipecatClientOptions(
            transport: transport,
            enableMic: true,
            enableCam: false
        ))
    }
    
    // Public convenience initializer
    public convenience init(apiKey: String) {
        self.init(apiKey: apiKey, initialMessages: [], generationConfig: nil)
    }
    
    public func start() async throws {
        try await pipecatClient.initDevices()
        try await pipecatClient.connect(transportParams: nil)
    }
    
    public func disconnect() async {
        try? await pipecatClient.disconnect()
    }
    
    public var delegate: PipecatClientDelegate? {
        get { transport.delegate }
        set { transport.delegate = newValue }
    }
}
