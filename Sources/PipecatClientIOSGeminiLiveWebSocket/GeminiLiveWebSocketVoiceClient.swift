import Foundation
import PipecatClientIOS

public class GeminiLiveWebSocketVoiceClient {
    private let pipecatClient: PipecatClient
    private let transport: GeminiLiveWebSocketTransport
    
    public init(apiKey: String, initialMessages: [WebSocketMessages.Outbound.TextInput] = [], generationConfig: Value? = nil) {
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
    
    public func start() async throws {
        try await pipecatClient.initDevices()
        try await pipecatClient.connect()
    }
    
    public func disconnect() async {
        try? await pipecatClient.disconnect()
    }
    
    public var delegate: PipecatClientDelegate? {
        get { transport.delegate }
        set { transport.delegate = newValue }
    }
}
