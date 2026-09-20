import Foundation
import Testing
@testable import SwitcherCore

struct PipeReaderTests {
    @Test func stoppingAnIdlePipeDoesNotWaitForItsWriter() throws {
        for _ in 0..<20 {
            let pipe = Pipe()
            let reader = try PipeReader(handle: pipe.fileHandleForReading) { _ in }
            reader.stop()
            reader.stop()
            let data = Data("writer remains open".utf8)
            try pipe.fileHandleForWriting.write(contentsOf: data)
            #expect(try pipe.fileHandleForReading.read(upToCount: data.count) == data)
            try pipe.fileHandleForWriting.close()
            try pipe.fileHandleForReading.close()
        }
    }

    @Test func deliversAllBytesBeforeEOF() async throws {
        let pipe = Pipe()
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        let reader = try PipeReader(handle: pipe.fileHandleForReading) { data in
            if let data { continuation.yield(data) } else { continuation.finish() }
        }
        defer { reader.stop() }
        let expected = Data(repeating: 0x61, count: 20_000)
        try pipe.fileHandleForWriting.write(contentsOf: expected)
        try pipe.fileHandleForWriting.close()
        var received = Data()
        for await data in stream { received.append(data) }
        #expect(received == expected)
    }
}
