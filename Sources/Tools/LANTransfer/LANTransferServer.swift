import Darwin
import Foundation
import Network
import Security
import SystemConfiguration

struct LANTransferAddress: Equatable {
    let interface: String
    let ip: String
    let network: UInt32
    let mask: UInt32

    static func available() -> [Self] {
        var entries: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&entries) == 0 else { return [] }
        defer { freeifaddrs(entries) }

        var addresses: [Self] = []
        var cursor = entries
        while let entry = cursor?.pointee {
            cursor = entry.ifa_next
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("en"), entry.ifa_flags & UInt32(IFF_UP | IFF_RUNNING) == UInt32(IFF_UP | IFF_RUNNING),
                  let address = entry.ifa_addr, address.pointee.sa_family == AF_INET,
                  let netmask = entry.ifa_netmask else { continue }
            let ip = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr
            let mask = UnsafeRawPointer(netmask).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr
            let bytes = withUnsafeBytes(of: ip) { Array($0) }
            guard mask != 0, bytes[0] > 0, bytes[0] != 127, bytes[0] < 224 else { continue }
            addresses.append(Self(interface: name, ip: bytes.map(String.init).joined(separator: "."),
                                  network: ip & mask, mask: mask))
        }
        let store = SCDynamicStoreCreate(nil, "MakeTools" as CFString, nil, nil)
        let state = store.flatMap { SCDynamicStoreCopyValue($0, "State:/Network/Global/IPv4" as CFString) } as? [String: Any]
        let primary = state?["PrimaryInterface"] as? String
        return addresses.sorted {
            let lhsLinkLocal = $0.ip.hasPrefix("169.254.")
            let rhsLinkLocal = $1.ip.hasPrefix("169.254.")
            if lhsLinkLocal != rhsLinkLocal { return !lhsLinkLocal }
            if ($0.interface == primary) != ($1.interface == primary) { return $0.interface == primary }
            return ($0.interface, $0.ip) < ($1.interface, $1.ip)
        }
    }

    func includes(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(.ipv4(address), _) = endpoint else { return false }
        return address.rawValue.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } & mask == network
    }
}

private final class LANTransferDestination {
    private let descriptor: Int32

    init(_ directory: URL) throws {
        descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    deinit { close(descriptor) }

    func temporaryFile() throws -> (String, FileHandle) {
        let name = ".maketools-upload-\(UUID().uuidString)"
        let fd = openat(descriptor, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return (name, FileHandle(fileDescriptor: fd, closeOnDealloc: true))
    }

    func remove(_ name: String) {
        _ = unlinkat(descriptor, name, 0)
    }

    func save(_ temporaryName: String, as originalName: String) throws -> String {
        let ext = (originalName as NSString).pathExtension
        let suffix = ext.isEmpty ? "" : "." + ext
        let stem = (originalName as NSString).deletingPathExtension
        for index in 1...10_000 {
            let numbering = " (\(index))"
            var candidate = originalName
            if index > 1 {
                // Keep the extension when it leaves space for the original stem.
                let keepsExtension = (numbering + suffix).utf8.count < 255
                let ending = keepsExtension ? numbering + suffix : numbering
                var prefix = keepsExtension ? stem : originalName
                let prefixLimit = 255 - ending.utf8.count
                while prefix.utf8.count > prefixLimit { prefix.removeLast() }
                candidate = prefix + ending
            }
            if renameatx_np(descriptor, temporaryName, descriptor, candidate, UInt32(RENAME_EXCL)) == 0 {
                return candidate
            }
            let code = errno
            guard code == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
        }
        throw POSIXError(.EEXIST)
    }
}

final class LANTransferServer {
    enum Event {
        case ready(URL)
        case failed(String)
        case received(String)
    }

    private let addresses: () -> [LANTransferAddress]
    private let queue = DispatchQueue(label: "com.make.MakeTools.LANTransfer", qos: .userInitiated)
    private var listener: NWListener?
    private var interfaceTimer: DispatchSourceTimer?
    private var connections: [UUID: LANTransferConnection] = [:]

    init(addresses: @escaping () -> [LANTransferAddress] = LANTransferAddress.available) {
        self.addresses = addresses
    }

    func start(port: UInt16, directory: URL, onEvent: @escaping (Event) -> Void) {
        queue.async { [self] in
            self.stopListening()
            guard let address = self.addresses().first, let ip = IPv4Address(address.ip) else {
                onEvent(.failed(L10n.text("lanTransfer.noLocalIpv4AddressIsAvailableConnect", "未找到可用的局域网 IPv4 地址，请连接 Wi-Fi 或有线网络。")))
                return
            }

            let destination: LANTransferDestination
            do {
                destination = try LANTransferDestination(directory)
                let (name, file) = try destination.temporaryFile()
                destination.remove(name)
                try file.close()
            } catch {
                onEvent(.failed(L10n.text("lanTransfer.theDestinationIsUnwritableChooseAWritable", "无法写入保存目录，请选择可写入的文件夹。")))
                return
            }

            var randomBytes = [UInt8](repeating: 0, count: 24)
            let randomStatus = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            guard randomStatus == errSecSuccess else {
                onEvent(.failed(L10n.text("lanTransfer.couldNotGenerateAnUploadLinkTry", "无法生成接收链接，请重试。")))
                return
            }
            let token = randomBytes.map { String(format: "%02x", $0) }.joined()
            let parameters = NWParameters.tcp
            let endpointPort = NWEndpoint.Port(rawValue: port) ?? .any
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(ip), port: endpointPort)

            do {
                let listener = try NWListener(using: parameters)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self, let listener, self.listener === listener else { return }
                    switch state {
                    case .ready:
                        guard let boundPort = listener.port, port == 0 || boundPort == endpointPort,
                              let url = URL(string: "http://\(address.ip):\(boundPort.rawValue)/\(token)/") else {
                            self.stopListening()
                            onEvent(.failed(L10n.text("lanTransfer.couldNotStartOnThatPortChange", "无法在指定端口启动，请修改端口后重试。")))
                            return
                        }
                        self.monitor(address: address, onEvent: onEvent)
                        onEvent(.ready(url))
                    case .failed(let error), .waiting(let error):
                        self.stopListening()
                        onEvent(.failed(Self.message(for: error, port: port)))
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self, weak listener] connection in
                    guard let self, let listener, self.listener === listener,
                          let boundPort = listener.port, self.connections.count < 8,
                          address.includes(connection.endpoint) else {
                        connection.cancel()
                        return
                    }
                    let id = UUID()
                    let host = "\(address.ip):\(boundPort.rawValue)"
                    let client = LANTransferConnection(connection: connection, queue: self.queue, host: host,
                                                       token: token, destination: destination)
                    self.connections[id] = client
                    client.start(onReceived: { onEvent(.received($0)) }, onClose: { [weak self] in
                        self?.connections[id] = nil
                    })
                }
                listener.start(queue: self.queue)
            } catch {
                onEvent(.failed(Self.message(for: error, port: port)))
            }
        }
    }

    func stop() {
        queue.async { self.stopListening() }
    }

    func shutdown() {
        queue.sync { stopListening() }
    }

    private func stopListening() {
        interfaceTimer?.cancel()
        interfaceTimer = nil
        listener?.cancel()
        listener = nil
        let active = Array(connections.values)
        connections.removeAll()
        for client in active { client.close() }
    }

    private func monitor(address: LANTransferAddress, onEvent: @escaping (Event) -> Void) {
        interfaceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 3, repeating: 3, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            guard let self, !self.addresses().contains(address) else { return }
            self.stopListening()
            onEvent(.failed(L10n.text("lanTransfer.theLocalNetworkAddressChangedTurnReception", "局域网地址已变化，请重新开启接收以生成新链接。")))
        }
        interfaceTimer = timer
        timer.resume()
    }

    private static func message(for error: Error, port: UInt16) -> String {
        if case NWError.posix(.EADDRINUSE) = error {
            return L10n.text("lanTransfer.portIsInUseChooseAnotherPort", "端口 {arg1} 已被占用，请更换端口。", ["arg1": String(describing: port)])
        }
        return L10n.text("lanTransfer.couldNotListenOnPort", "无法监听端口 {arg1}。{arg2}", ["arg1": String(describing: port), "arg2": String(describing: error.localizedDescription)])
    }
}

private final class LANTransferConnection {
    private static let headerEnd = Data([13, 10, 13, 10])
    private static let maximumHeader = 16 * 1024
    private static let maximumFile: Int64 = 5 * 1024 * 1024 * 1024

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let host: String
    private let path: String
    private let destination: LANTransferDestination
    private var timeout: DispatchSourceTimer?
    private var header = Data()
    private var upload: Upload?
    private var onReceived: ((String) -> Void)?
    private var onClose: (() -> Void)?
    private var isClosed = false

    private struct Upload {
        let name: String
        let temporaryName: String
        let file: FileHandle
        var remaining: Int64
    }

    init(connection: NWConnection, queue: DispatchQueue, host: String, token: String,
         destination: LANTransferDestination) {
        self.connection = connection
        self.queue = queue
        self.host = host
        self.path = "/\(token)/"
        self.destination = destination
    }

    func start(onReceived: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.onReceived = onReceived
        self.onClose = onClose
        let timeout = DispatchSource.makeTimerSource(queue: queue)
        timeout.setEventHandler { [weak self] in self?.close() }
        self.timeout = timeout
        armTimeout()
        timeout.resume()
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.receive()
            case .failed, .cancelled: self?.close()
            default: break
            }
        }
        connection.start(queue: queue)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        timeout?.cancel()
        timeout = nil
        connection.cancel()
        if let upload {
            try? upload.file.close()
            destination.remove(upload.temporaryName)
            self.upload = nil
        }
        onClose?()
        onClose = nil
    }

    private func armTimeout() {
        timeout?.schedule(deadline: .now() + (upload == nil ? 15 : 60))
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, ended, error in
            guard let self, !self.isClosed else { return }
            guard error == nil else { self.close(); return }
            if let data, !data.isEmpty {
                if self.upload != nil {
                    self.armTimeout()
                    self.write(data, ended: ended)
                } else {
                    self.readHeader(data, ended: ended)
                }
            } else if ended {
                self.close()
            } else {
                self.receive()
            }
        }
    }

    private func readHeader(_ data: Data, ended: Bool) {
        header.append(data)
        guard let boundary = header.range(of: Self.headerEnd) else {
            if header.count > Self.maximumHeader { respond("431 Request Header Fields Too Large", L10n.text("lanTransfer.requestHeadersAreTooLarge", "请求头过大。")) }
            else if ended { close() }
            else { receive() }
            return
        }
        guard boundary.lowerBound <= Self.maximumHeader,
              let head = String(data: header[..<boundary.lowerBound], encoding: .ascii),
              let request = Request(head) else {
            respond("400 Bad Request", L10n.text("lanTransfer.invalidRequest", "请求格式无效。"))
            return
        }
        let body = Data(header[boundary.upperBound...])
        header.removeAll()

        guard request.fields["host"] == host, request.target.hasPrefix(path) else {
            respond("404 Not Found", L10n.text("lanTransfer.theUploadLinkIsInvalidGetThe", "接收链接无效。请在 Mac 上获取当前链接。"))
            return
        }
        if request.method == "GET", request.target == path {
            respond("200 OK", LANTransferPage.html, contentType: "text/html; charset=utf-8")
            return
        }
        guard request.method == "PUT" else {
            respond("405 Method Not Allowed", L10n.text("lanTransfer.openTheUploadPageOrUploadUsing", "请打开接收页面，或使用 PUT 上传。"))
            return
        }
        guard request.fields["origin"].map({ $0 == "http://\(host)" }) ?? true else {
            respond("403 Forbidden", L10n.text("lanTransfer.uploadFromTheReceptionPage", "请从接收页面上传。"))
            return
        }
        guard request.fields["transfer-encoding"] == nil,
              let size = request.fields["content-length"], !size.isEmpty,
              size.utf8.allSatisfy({ (48...57).contains($0) }), let length = Int64(size) else {
            respond("411 Length Required", L10n.text("lanTransfer.theFileSizeMustBeKnown", "需要已知文件大小。"))
            return
        }
        guard length <= Self.maximumFile else {
            respond("413 Content Too Large", L10n.text("lanTransfer.aSingleFileCannotExceed5Gib", "单个文件不能超过 5 GiB。"))
            return
        }
        let encodedName = String(request.target.dropFirst(path.count))
        guard let name = encodedName.removingPercentEncoding, !name.isEmpty, name != ".", name != "..",
              !encodedName.contains("?"), !encodedName.contains("#"),
              !name.contains("/"), !name.contains("\\"), !name.lowercased().hasPrefix(".maketools-upload-"),
              name.utf8.count <= 255, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            respond("400 Bad Request", L10n.text("lanTransfer.invalidFilename", "文件名无效。"))
            return
        }
        let expect = request.fields["expect"]
        guard expect == nil || expect?.lowercased() == "100-continue" else {
            respond("417 Expectation Failed", L10n.text("lanTransfer.couldNotProcessThisUploadRequest", "无法处理此上传请求。"))
            return
        }
        do {
            let (temporaryName, file) = try destination.temporaryFile()
            upload = Upload(name: name, temporaryName: temporaryName, file: file, remaining: length)
        } catch {
            respond("507 Insufficient Storage", L10n.text("lanTransfer.cannotWriteToTheDestinationFolderOn", "无法写入 Mac 上的保存目录。"))
            return
        }
        armTimeout()
        if expect != nil && length > 0 && body.isEmpty && !ended {
            connection.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), completion: .contentProcessed { [weak self] error in
                if error == nil { self?.receive() } else { self?.close() }
            })
        } else {
            write(body, ended: ended)
        }
    }

    private func write(_ data: Data, ended: Bool) {
        guard var current = upload else { return }
        guard data.count <= current.remaining else {
            respond("400 Bad Request", L10n.text("lanTransfer.theUploadExceedsTheDeclaredFileSize", "上传数据超过声明的文件大小。"))
            return
        }
        do {
            try current.file.write(contentsOf: data)
            current.remaining -= Int64(data.count)
            upload = current
            if current.remaining == 0 {
                try current.file.close()
                let savedName = try destination.save(current.temporaryName, as: current.name)
                upload = nil
                onReceived?(savedName)
                respond("201 Created", savedName)
            } else if ended {
                close()
            } else {
                receive()
            }
        } catch {
            respond("507 Insufficient Storage", L10n.text("lanTransfer.couldNotSaveTheFileCheckFolder", "保存失败，请检查目录权限和可用空间。"))
        }
    }

    private func respond(_ status: String, _ text: String, contentType: String = "text/plain; charset=utf-8") {
        let body = Data(text.utf8)
        let headers = [
            "HTTP/1.1 \(status)", "Content-Type: \(contentType)", "Content-Length: \(body.count)",
            "Connection: close", "Cache-Control: no-store", "Referrer-Policy: no-referrer",
            "X-Content-Type-Options: nosniff",
            "Content-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
        ]
        var response = Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in self?.close() })
    }

    private struct Request {
        let method: Substring
        let target: Substring
        var fields: [String: String] = [:]

        init?(_ head: String) {
            let lines = head.components(separatedBy: "\r\n")
            guard let first = lines.first else { return nil }
            let parts = first.split(separator: " ", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[2] == "HTTP/1.1",
                  !parts[0].isEmpty, parts[1].hasPrefix("/") else { return nil }
            method = parts[0]
            target = parts[1]
            for line in lines.dropFirst() {
                let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard pair.count == 2, !pair[0].isEmpty,
                      pair[0].utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) ||
                          (97...122).contains($0) || $0 == 45 || $0 == 95 }),
                      !pair[1].utf8.contains(where: { $0 < 32 && $0 != 9 || $0 == 127 }) else { return nil }
                let key = pair[0].lowercased()
                guard fields[key] == nil else { return nil }
                fields[key] = pair[1].trimmingCharacters(in: .whitespaces)
            }
        }
    }
}
