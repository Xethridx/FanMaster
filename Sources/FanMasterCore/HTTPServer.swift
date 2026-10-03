import Foundation

// MARK: - Tiny HTTP Server (no external dependencies)

public class HTTPServer {
    private let port: UInt16
    private var serverSocket: Int32 = -1
    private var isRunning = false
    private var requestHandler: ((String, String) -> (Int, String, String))?
    
    public init(port: UInt16 = 7474) {
        self.port = port
    }
    
    /// Set the request handler: (method, path) -> (statusCode, contentType, body)
    public func onRequest(_ handler: @escaping (String, String) -> (Int, String, String)) {
        self.requestHandler = handler
    }
    
    public func start() throws {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw NSError(domain: "HTTPServer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot create socket"])
        }
        
        var yes: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw NSError(domain: "HTTPServer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Cannot bind to port \(port)"])
        }
        
        listen(serverSocket, 10)
        isRunning = true
        
        // Accept connections in background
        Thread.detachNewThread { [weak self] in
            self?.acceptLoop()
        }
        
        print("🌡️  FanMaster HTTP server listening on http://localhost:\(port)")
    }
    
    public func stop() {
        isRunning = false
        close(serverSocket)
    }
    
    private func acceptLoop() {
        while isRunning {
            var clientAddr = sockaddr_in()
            var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(serverSocket, $0, &clientLen)
                }
            }
            guard clientSocket >= 0 else { continue }
            
            Thread.detachNewThread { [weak self] in
                self?.handleClient(clientSocket)
            }
        }
    }
    
    private func handleClient(_ socket: Int32) {
        defer { close(socket) }
        
        var buffer = [UInt8](repeating: 0, count: 8192)
        let bytesRead = recv(socket, &buffer, buffer.count - 1, 0)
        guard bytesRead > 0 else { return }
        
        let request = String(bytes: buffer.prefix(bytesRead), encoding: .utf8) ?? ""
        let lines = request.components(separatedBy: "\r\n")
        let requestLine = lines.first ?? ""
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return }
        
        let method = parts[0]
        let rawPath = parts[1]
        // Read body if POST (path is embedded in rawPath, parsed by handler)
        var body = ""
        if method == "POST", let bodyRange = request.range(of: "\r\n\r\n") {
            body = String(request[bodyRange.upperBound...])
        }
        _ = body
        
        let (statusCode, contentType, responseBody) = requestHandler?(method, rawPath) ?? (404, "text/plain", "Not Found")
        
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 201: statusText = "Created"
        case 400: statusText = "Bad Request"
        case 403: statusText = "Forbidden"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default:  statusText = "Unknown"
        }
        
        let responseData = responseBody.data(using: .utf8) ?? Data()
        let headers = """
        HTTP/1.1 \(statusCode) \(statusText)\r\n\
        Content-Type: \(contentType); charset=utf-8\r\n\
        Content-Length: \(responseData.count)\r\n\
        Access-Control-Allow-Origin: *\r\n\
        Connection: close\r\n\
        \r\n
        """
        
        let headerData = headers.data(using: .utf8)!
        _ = headerData.withUnsafeBytes { send(socket, $0.baseAddress!, headerData.count, 0) }
        _ = responseData.withUnsafeBytes { send(socket, $0.baseAddress!, responseData.count, 0) }
    }
}

// MARK: - JSON Helpers

public func jsonString(_ object: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]) else {
        return "{}"
    }
    return String(data: data, encoding: .utf8) ?? "{}"
}
