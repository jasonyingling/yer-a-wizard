import Cocoa
import AVFoundation

final class TestSocket: VoiceSocket {
    var incoming: (@Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void)?
    var sent: [[String: Any]] = []
    var closed = false
    var stall = false
    func resume() {}
    func receive(completionHandler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void) { incoming = completionHandler }
    func send(_ message: URLSessionWebSocketTask.Message, completionHandler: @escaping @Sendable (Error?) -> Void) {
        if case .string(let text) = message {
            sent.append(try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any])
        }
        if !stall { completionHandler(nil) }
    }
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) { closed = true }
    func emit(_ event: [String: Any]) {
        let callback = incoming; incoming = nil
        callback?(.success(.data(try! JSONSerialization.data(withJSONObject: event))))
    }
}
final class TestMicrophone: VoiceMicrophone {
    var running = false
    var onPCM: ((Data) -> Void)?
    func start(onPCM: @escaping (Data) -> Void) throws { running = true; self.onPCM = onPCM }
    func stop() { running = false }
}

@main struct VoiceTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.03)) }
        let pink = WandColor(hex: "#ff69b4")!
        precondition(pink.hex == "#FF69B4" && WandColor(color: pink.glow) == pink)
        precondition(WandColor(hex: "red") == nil && WandColor(hex: "#GG0000") == nil && WandColor(hex: "#00000000") == nil)
        let call: [String: Any] = ["type": "function_call", "name": "set_wand_color", "call_id": "call_1", "arguments": "{\"hex\":\"#ff69b4\"}"]
        precondition(WandColorCommand(item: call)?.color == pink)
        var invalid = call; invalid["name"] = "run_code"
        precondition(WandColorCommand(item: invalid) == nil)
        invalid = call; invalid["arguments"] = "{\"hex\":\"pink\"}"
        precondition(WandColorCommand(item: invalid) == nil)
        invalid["arguments"] = "{\"hex\":\"#FF69B4\",\"extra\":true}"
        precondition(WandColorCommand(item: invalid) == nil)
        let done: [String: Any] = ["type": "response.done", "response": ["status": "completed", "output": [call]]]

        var now = 10.0
        let socket = TestSocket(), mic = TestMicrophone()
        var permissionRequests = 0, connections = 0, changes: [WandColor] = []
        let controller = WandVoiceController(keyProvider: { "test-key-never-sent" }, permission: { completion in
            permissionRequests += 1; completion(true)
        }, makeSocket: { request in
            connections += 1
            precondition(request.url!.host == "api.openai.com" && request.url!.scheme == "wss")
            return socket
        }, makeMicrophone: { mic }, automatic: true, clock: { now })
        controller.onColor = { changes.append($0) }
        controller.observe(wand: true, active: true, at: now); drain()
        precondition(permissionRequests == 0 && connections == 0 && !mic.running, "Voice off never requests mic or connects")
        controller.toggleEnabled()
        controller.observe(wand: true, active: true, at: now); drain()
        precondition(connections == 1 && !mic.running, "Wait for server configuration before capturing")
        precondition(socket.sent.first?["type"] as? String == "session.update")
        let session = socket.sent.first?["session"] as! [String: Any]
        precondition(session["output_modalities"] as? [String] == ["text"])
        socket.emit(["type": "session.updated"]); drain()
        precondition(mic.running)
        mic.onPCM?(Data([0, 0, 1, 0])); drain()
        precondition(socket.sent.last?["type"] as? String == "input_audio_buffer.append")
        socket.emit(done); drain()
        precondition(changes == [pink], "Completed Realtime color command updates the picker")
        socket.emit(done); drain()
        precondition(changes.count == 1, "Duplicate tool events are ignored")
        let lateEvent = socket.incoming
        let lateAudio = mic.onPCM
        controller.toggleEnabled()
        precondition(socket.closed && !mic.running, "Off stops microphone and socket synchronously")
        let sentBefore = socket.sent.count
        lateAudio?(Data([0, 0])); lateEvent?(.success(.data(try! JSONSerialization.data(withJSONObject: done)))); drain()
        precondition(changes.count == 1 && socket.sent.count == sentBefore, "Late callbacks cannot send audio or apply commands after off")

        let waiting = TestSocket(), waitingMic = TestMicrophone()
        var grantPermission: ((Bool) -> Void)?
        var unexpectedConnection = false
        let cancelled = WandVoiceController(keyProvider: { "test" }, permission: { grantPermission = $0 },
            makeSocket: { _ in unexpectedConnection = true; return waiting }, makeMicrophone: { waitingMic }, automatic: true, clock: { now })
        cancelled.toggleEnabled(); cancelled.observe(wand: true, active: true, at: now)
        cancelled.toggleEnabled(); grantPermission?(true); drain()
        precondition(!unexpectedConnection && !waitingMic.running, "Permission response after disabling cannot restart voice")

        let manualSocket = TestSocket(), manualMic = TestMicrophone()
        let manual = WandVoiceController(keyProvider: { "test" }, permission: { $0(true) }, makeSocket: { _ in manualSocket },
            makeMicrophone: { manualMic }, automatic: false, clock: { now })
        manual.toggleEnabled(); manual.observe(wand: true, active: true, at: now); drain()
        precondition(manualSocket.sent.isEmpty, "Manual mode ignores wand raises")
        manual.toggleManual(); drain(); manualSocket.emit(["type": "session.updated"]); drain()
        precondition(manualMic.running)
        manual.observe(wand: false, active: false, at: now)
        precondition(!manualMic.running && manualSocket.closed, "Losing focus immediately stops listening")

        let lostSocket = TestSocket(), lostMic = TestMicrophone()
        var statuses: [String] = []
        let lost = WandVoiceController(keyProvider: { "test" }, permission: { $0(true) }, makeSocket: { _ in lostSocket },
            makeMicrophone: { lostMic }, automatic: true, clock: { now })
        lost.onState = { _, _, _, text in statuses.append(text) }
        lost.toggleEnabled(); lost.observe(wand: true, active: true, at: now); drain()
        lostSocket.emit(["type": "session.updated"]); drain()
        now += 1; lost.observe(wand: false, active: true, at: now)
        precondition(lostMic.running, "Short tracking gaps allow finishing a command")
        now += 0.6; lost.observe(wand: false, active: true, at: now)
        precondition(!lostMic.running && lostSocket.closed, "Lowered wand closes the session")

        let errorSocket = TestSocket(), errorMic = TestMicrophone()
        var attempts = 0
        let failing = WandVoiceController(keyProvider: { "test" }, permission: { $0(true) }, makeSocket: { _ in attempts += 1; return errorSocket },
            makeMicrophone: { errorMic }, automatic: true, clock: { now })
        failing.toggleEnabled(); failing.observe(wand: true, active: true, at: now); drain()
        errorSocket.emit(["type": "error", "error": ["code": "invalid_api_key"]]); drain()
        failing.observe(wand: true, active: true, at: now); drain()
        precondition(attempts == 1 && !errorMic.running && errorSocket.closed, "Errors stop listening without reconnect loops")
        var missingKeyStatus = ""
        let noKey = WandVoiceController(keyProvider: { nil }, permission: { _ in preconditionFailure("No key must not request microphone") }, automatic: true)
        noKey.onState = { _, _, _, text in missingKeyStatus = text }
        noKey.toggleEnabled(); noKey.observe(wand: true, active: true)
        precondition(missingKeyStatus.contains("API key"))
        let slowSocket = TestSocket(), slowMic = TestMicrophone()
        let slow = WandVoiceController(keyProvider: { "test" }, permission: { $0(true) }, makeSocket: { _ in slowSocket },
            makeMicrophone: { slowMic }, automatic: true, clock: { now })
        slow.toggleEnabled(); slow.observe(wand: true, active: true, at: now); drain()
        slowSocket.emit(["type": "session.updated"]); drain(); slowSocket.stall = true
        for _ in 0..<20 { slowMic.onPCM?(Data([0, 0])) }
        drain()
        precondition(!slowMic.running && slowSocket.closed, "Slow networks stop capture before buffering unbounded audio")
        let denied = WandVoiceController(keyProvider: { "test" }, permission: { $0(false) },
            makeSocket: { _ in preconditionFailure("Denied microphone permission must not connect") }, automatic: true)
        denied.toggleEnabled(); denied.observe(wand: true, active: true); drain()
        denied.shutdown(); slow.shutdown()
        controller.shutdown(); cancelled.shutdown(); manual.shutdown(); lost.shutdown(); failing.shutdown(); noKey.shutdown()
        print("PASS: color parsing, tool validation, session configuration, audio gating, color callbacks, duplicate rejection, immediate off, late callbacks, permission cancellation, manual mode, focus loss, tracking loss, missing key and API errors")
    }
}
