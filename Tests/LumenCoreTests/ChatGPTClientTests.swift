import XCTest

@testable import LumenCore

final class ChatGPTClientTests: XCTestCase {
    private var directories: [URL] = []
    private var clients: [ChatGPTClient] = []

    override func tearDown() async throws {
        for client in clients { await client.disconnect() }
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
        clients = []
        directories = []
    }

    private func fixture(
        _ mode: String = "normal", requestTimeout: TimeInterval = 2,
        turnTimeout: TimeInterval = 3
    ) throws -> (ChatGPTClient, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-protocol-" + UUID().uuidString)
        let home = root.appendingPathComponent("auth")
        let cwd = root.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["mode": mode]).write(
            to: home.appendingPathComponent("scenario.json"))
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let executable = package.appendingPathComponent("scripts/mock-codex.py")
        let client = ChatGPTClient(
            homeDirectory: home, workingDirectory: cwd, executableURL: executable,
            requestTimeout: requestTimeout, turnTimeout: turnTimeout)
        directories.append(root)
        clients.append(client)
        return (client, home)
    }

    private func requests(_ home: URL) throws -> [[String: Any]] {
        let text = try String(contentsOf: home.appendingPathComponent("mock-requests.jsonl"))
        return try text.split(separator: "\n").map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
    }

    private func collect(_ client: ChatGPTClient, image: Data? = nil) async throws -> String {
        let stream = await client.stream(
            messages: [.init(role: .user, text: "What is on the screen?")],
            instructions: "Be concise", context: "Selected context", imageJPEG: image, model: "fixture-model")
        var text = ""
        for try await delta in stream { text += delta }
        return text
    }

    func testManagedLoginAndIsolatedEnvironment() async throws {
        let (client, home) = try fixture()
        let account = try await client.checkAccount()
        XCTAssertTrue(account.isSignedIn)
        XCTAssertEqual(account.summary, "fixture@example.test")
        let url = try await client.beginLogin()
        XCTAssertEqual(url.host, "auth.openai.com")
        let events = try requests(home)
        let environment = try XCTUnwrap(events.first?["environment"] as? [String: Any])
        XCTAssertEqual(environment["CODEX_HOME"] as? String, home.path)
        XCTAssertEqual(environment["hasAPIKey"] as? Bool, false)
        let arguments = try XCTUnwrap(environment["arguments"] as? [String])
        let disabledFeatures = Set(zip(arguments, arguments.dropFirst()).compactMap { $0 == "--disable" ? $1 : nil })
        XCTAssertTrue(
            Set(["shell_tool", "code_mode", "code_mode_host", "unified_exec", "view_image", "workspace_dependencies"])
                .isSubset(of: disabledFeatures))
        XCTAssertEqual(events.compactMap { $0["method"] as? String }.prefix(2), ["initialize", "initialized"])
        let login = try XCTUnwrap(
            events.first { $0["method"] as? String == "account/login/start" }?["params"] as? [String: Any])
        XCTAssertEqual(login["type"] as? String, "chatgpt")
        XCTAssertNil(login["accessToken"])
        XCTAssertNil(login["apiKey"])
    }

    func testModelsUseServerCatalogAndPagination() async throws {
        let (client, _) = try fixture()
        let models = try await client.listModels()
        XCTAssertEqual(models.map(\.id), ["fixture-default", "fixture-model"])
        XCTAssertEqual(models.first?.title, "Fixture default")
    }

    func testStreamsDeltasOnceAndPassesImageWithNoEnvironmentAccess() async throws {
        let (client, home) = try fixture()
        let text = try await collect(client, image: Data([0xff, 0xd8, 0xff]))
        XCTAssertEqual(text, "Hello world")
        let events = try requests(home)
        let thread = try XCTUnwrap(
            events.first { $0["method"] as? String == "thread/start" }?["params"] as? [String: Any])
        XCTAssertEqual(thread["ephemeral"] as? Bool, true)
        XCTAssertEqual(thread["sandbox"] as? String, "read-only")
        XCTAssertEqual(thread["approvalPolicy"] as? String, "never")
        XCTAssertEqual((thread["environments"] as? [Any])?.count, 0)
        let turn = try XCTUnwrap(events.first { $0["method"] as? String == "turn/start" }?["params"] as? [String: Any])
        let input = try XCTUnwrap(turn["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 2)
        XCTAssertEqual(input[1]["url"] as? String, "data:image/jpeg;base64,/9j/")
        XCTAssertTrue((input[0]["text"] as? String)?.contains("Selected context") == true)
    }

    func testFinalItemIsUsedWhenServerDoesNotSendDeltas() async throws {
        let (client, _) = try fixture("fallback")
        let text = try await collect(client)
        XCTAssertEqual(text, "Hello world")
    }

    func testServerErrorsAndProcessExitAreReported() async throws {
        for mode in ["error", "crash"] {
            let (client, _) = try fixture(mode)
            do {
                _ = try await client.checkAccount()
                XCTFail("Expected \(mode) error")
            } catch {
                if mode == "error" {
                    XCTAssertEqual(error as? ChatGPTClientError, .server("Sign-in expired"))
                } else {
                    XCTAssertEqual(error as? ChatGPTClientError, .disconnected)
                }
            }
        }
    }

    func testUnsignedAndAPIKeyAccountsCannotStartSubscriptionTurns() async throws {
        for mode in ["signed-out", "api-key-account"] {
            let (client, home) = try fixture(mode)
            do {
                _ = try await collect(client)
                XCTFail("Expected sign-in requirement")
            } catch { XCTAssertEqual(error as? ChatGPTClientError, .notSignedIn) }
            XCTAssertFalse(try requests(home).contains { $0["method"] as? String == "thread/start" })
        }
    }

    func testFailedAndInterruptedTurnsPropagateTheirStatus() async throws {
        let (failed, _) = try fixture("failed")
        do {
            _ = try await collect(failed)
            XCTFail("Expected failed turn")
        } catch { XCTAssertEqual(error as? ChatGPTClientError, .server("Fixture usage limit reached")) }
        let (interrupted, _) = try fixture("interrupted")
        do {
            _ = try await collect(interrupted)
            XCTFail("Expected interruption")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testToolRequestsAreRejected() async throws {
        let (client, _) = try fixture("approval")
        do {
            _ = try await collect(client)
            XCTFail("Expected tool rejection")
        } catch { XCTAssertEqual(error as? ChatGPTClientError, .unsupportedTool) }
    }

    func testRequestAndTurnTimeouts() async throws {
        let (hangingConnection, _) = try fixture("hang-initialize", requestTimeout: 0.1)
        do {
            _ = try await hangingConnection.checkAccount()
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual(error as? ChatGPTClientError, .timedOut) }
        let (hangingTurn, _) = try fixture("hang-turn", turnTimeout: 0.1)
        do {
            _ = try await collect(hangingTurn)
            XCTFail("Expected turn timeout")
        } catch { XCTAssertEqual(error as? ChatGPTClientError, .timedOut) }
    }

    func testInvalidLoginURLIsRejected() async throws {
        let (client, _) = try fixture("bad-login-url")
        do {
            _ = try await client.beginLogin()
            XCTFail("Expected URL validation")
        } catch { XCTAssertTrue(error is ChatGPTClientError) }
    }

    func testExistingCodexHomeCannotBeUsed() async throws {
        let client = ChatGPTClient(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"),
            workingDirectory: FileManager.default.temporaryDirectory)
        clients.append(client)
        do {
            _ = try await client.checkAccount()
            XCTFail("Expected isolated-home requirement")
        } catch { XCTAssertEqual(error as? ChatGPTClientError, .isolatedHomeRequired) }
    }

    func testInstalledCLIHandshakeWithEmptyIsolatedHome() async throws {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
        ]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("The installed Codex CLI compatibility check requires the desktop app.")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-empty-cli-" + UUID().uuidString)
        directories.append(root)
        let client = ChatGPTClient(
            homeDirectory: root.appendingPathComponent("auth"),
            workingDirectory: root.appendingPathComponent("workspace"),
            executableURL: URL(fileURLWithPath: path), requestTimeout: 10)
        clients.append(client)
        // Empty private CODEX_HOME; this performs only initialize/initialized/account/read.
        // It never starts login, discovers models, or requests inference.
        let account = try await client.checkAccount()
        XCTAssertFalse(account.isSignedIn)
    }

    func testConsumerCancellationStopsTurnAndAllowsReconnect() async throws {
        let (client, _) = try fixture("hang-turn")
        let received = expectation(description: "Received a delta")
        let task = Task {
            let stream = await client.stream(
                messages: [.init(role: .user, text: "Hi")], instructions: "", context: "", imageJPEG: nil, model: "")
            for try await _ in stream { received.fulfill() }
        }
        await fulfillment(of: [received], timeout: 2)
        task.cancel()
        _ = await task.result
        // Cancellation cleanup is actor work queued by AsyncThrowingStream.
        try await Task.sleep(nanoseconds: 20_000_000)
        let account = try await client.checkAccount()
        XCTAssertTrue(account.isSignedIn)
    }
}
