import Foundation
#if os(Windows)
import SwitcherPlatform
#endif

/// Owns pipe monitoring and guarantees that stopping it releases a blocked reader.
final class PipeReader: @unchecked Sendable {
    #if os(Windows)
    private final class Callback: @unchecked Sendable {
        let receive: @Sendable (Data?) -> Void
        init(_ receive: @escaping @Sendable (Data?) -> Void) { self.receive = receive }
    }
    private let callback: Callback
    private var reader: OpaquePointer?

    init(handle: FileHandle, receive: @escaping @Sendable (Data?) -> Void) throws {
        callback = Callback(receive)
        // Foundation's readabilityHandler uses a second synchronous read to monitor
        // Windows pipes. Concurrent sessions can stall that shared dispatch machinery.
        reader = switcher_pipe_reader_start(handle._handle, { context, bytes, count in
            guard let context else { return }
            let callback = Unmanaged<Callback>.fromOpaque(context).takeUnretainedValue()
            callback.receive(bytes.map { Data(bytes: $0, count: count) })
        }, Unmanaged.passUnretained(callback).toOpaque())
        guard reader != nil else {
            throw CodexClientError.processLaunchFailed("Could not start the Codex pipe reader.")
        }
    }

    func stop() {
        if let reader {
            switcher_pipe_reader_stop(reader)
            self.reader = nil
        }
    }
    #else
    private let handle: FileHandle

    init(handle: FileHandle, receive: @escaping @Sendable (Data?) -> Void) throws {
        self.handle = handle
        handle.readabilityHandler = { readable in
            let data = readable.availableData
            if data.isEmpty { readable.readabilityHandler = nil }
            receive(data.isEmpty ? nil : data)
        }
    }

    func stop() { handle.readabilityHandler = nil }
    #endif

    deinit { stop() }
}
