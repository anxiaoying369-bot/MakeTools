import Darwin
import Foundation
import Network

@main
enum LANTransferTests {
    struct Failure: Error {
        let reason: String
        init(_ reason: String) { self.reason = reason }
    }

    static func main() async {
        do {
            try await run()
            print("LANTransferTests: browser page, uploads, filename validation, cleanup, and session rotation passed.")
        } catch {
            fputs("LANTransferTests failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: directory) }

        let loopback = LANTransferAddress(interface: "lo0", ip: "127.0.0.1",
                                          network: inet_addr("127.0.0.0"), mask: inet_addr("255.0.0.0"))
        let server = LANTransferServer(addresses: { [loopback] })
        defer { server.shutdown() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        let client = URLSession(configuration: configuration)
        defer { client.invalidateAndCancel() }

        let url = try await start(server, directory: directory, port: 0)
        let (page, pageResponse) = try await client.data(from: url)
        try require((pageResponse as? HTTPURLResponse)?.statusCode == 200 &&
                    String(decoding: page, as: UTF8.self).contains("选择文件并上传"), "The link should serve the upload page")

        let payload = Data((0..<(320 * 1024)).map { UInt8(truncatingIfNeeded: $0) })
        let name = "测试 文件.bin"
        let upload = url.appendingPathComponent(name)
        let first = try await send(client, url: upload, body: payload)
        try require(first.0 == 201 && first.1 == name, "Upload should preserve the complete filename")
        let saved = try Data(contentsOf: directory.appendingPathComponent(name))
        try require(saved == payload, "The saved file should match a multi-chunk request exactly")

        let second = try await send(client, url: upload, body: Data())
        let original = try Data(contentsOf: directory.appendingPathComponent(name))
        let duplicate = try Data(contentsOf: directory.appendingPathComponent("测试 文件 (2).bin"))
        try require(second.0 == 201 && original == payload && duplicate.isEmpty,
                    "A zero-byte duplicate should get a new name and leave the first file intact")

        let multibyteCharacter = "q\u{0301}\u{0301}\u{0301}\u{0301}"
        let longName = "x.z" + String(repeating: multibyteCharacter, count: 28)
        let longUpload = url.appendingPathComponent(longName)
        let firstLong = try await send(client, url: longUpload, body: Data([1]))
        try require(firstLong.0 == 201 && firstLong.1 == longName,
                    "A 255-byte filename should be saved as received (HTTP \(firstLong.0))")
        let secondLong = try await send(client, url: longUpload, body: Data([2]))
        try require(secondLong.0 == 201 && secondLong.1.hasSuffix(" (2)") && secondLong.1.utf8.count <= 255,
                    "A duplicate with a long multibyte extension should get a valid numbered name")
        let longOriginal = try Data(contentsOf: directory.appendingPathComponent(longName))
        let longDuplicate = try Data(contentsOf: directory.appendingPathComponent(secondLong.1))
        try require(longOriginal == Data([1]) && longDuplicate == Data([2]), "Both long-named uploads should retain their contents")

        let unsafe = URL(string: url.absoluteString + "..%2Foutside.txt")!
        let traversal = try await send(client, url: unsafe, body: Data([1]))
        try require(traversal.0 == 400, "Encoded directory separators should be rejected")

        let wrongHost = try await send(client, url: upload, body: Data([1]), headers: ["Host": "other.example"])
        try require(wrongHost.0 == 404, "The address in Host should match the listening endpoint")
        let wrongOrigin = try await send(client, url: upload, body: Data([1]), headers: ["Origin": "http://other.example"])
        try require(wrongOrigin.0 == 403, "An upload from another website should be rejected")

        let occupiedPort = UInt16(url.port!)
        let competingServer = LANTransferServer(addresses: { [loopback] })
        defer { competingServer.shutdown() }
        do {
            _ = try await start(competingServer, directory: directory, port: occupiedPort)
            throw Failure("A second receiver should never silently share the port")
        } catch let failure as Failure {
            try require(failure.reason.contains("已被占用"), "Port conflicts should show a specific error: \(failure.reason)")
        }

        try await verifyPartialUpload(url: url, directory: directory)
        server.shutdown()
        do {
            _ = try await client.data(from: url)
            throw Failure("A stopped receiver should stop accepting connections")
        } catch is URLError {
            // The HTTP server should no longer be available.
        }

        let reopened = try await start(server, directory: directory, port: occupiedPort)
        let (_, oldResponse) = try await client.data(from: url)
        try require(reopened != url && (oldResponse as? HTTPURLResponse)?.statusCode == 404,
                    "Restarting on the same port should invalidate the old link")
    }

    private static func start(_ server: LANTransferServer, directory: URL, port: UInt16) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            var didStart = false
            server.start(port: port, directory: directory) { event in
                guard !didStart else { return }
                switch event {
                case .ready(let url):
                    didStart = true
                    continuation.resume(returning: url)
                case .failed(let error):
                    didStart = true
                    continuation.resume(throwing: Failure(error))
                case .received: break
                }
            }
        }
    }

    private static func send(_ client: URLSession, url: URL, body: Data, headers: [String: String] = [:]) async throws -> (Int, String) {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = body
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await client.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: data, as: UTF8.self))
    }

    private static func verifyPartialUpload(url: URL, directory: URL) async throws {
        let port = NWEndpoint.Port(rawValue: UInt16(url.port!))!
        let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        defer { connection.cancel() }
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)!.percentEncodedPath
        let request = "PUT \(path)unfinished.txt HTTP/1.1\r\nHost: 127.0.0.1:\(port.rawValue)\r\nContent-Length: 50\r\n\r\npart"
        let queue = DispatchQueue(label: "LANTransferTests.partial")
        connection.stateUpdateHandler = { [weak connection] state in
            if case .ready = state { connection?.send(content: Data(request.utf8), completion: .contentProcessed { _ in }) }
        }
        connection.start(queue: queue)
        try await waitForPartialFile(in: directory, present: true)
        connection.cancel()
        try await waitForPartialFile(in: directory, present: false)
        try require(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("unfinished.txt").path),
                    "An interrupted upload should never be visible as a final file")
    }

    private static func waitForPartialFile(in directory: URL, present: Bool) async throws {
        for _ in 0..<100 {
            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            if files.contains(where: { $0.hasPrefix(".maketools-upload-") }) == present { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw Failure("Temporary file visibility did not reach \(present)")
    }

    private static func require(_ condition: Bool, _ reason: String) throws {
        if !condition { throw Failure(reason) }
    }
}
