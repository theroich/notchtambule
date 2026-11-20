//
//  ProcessOutputParserTests.swift
//  NotchTubeAudioTests
//

import Foundation
import Testing
@testable import NotchTubeAudio

struct ProcessOutputParserTests {
    @Test(arguments: [
        ("download:  45.3%", 45.3),
        ("download:100.0%", 100.0),
        ("[download]  12.0% of 3.2MiB", 12.0),
        ("  45.3%", 45.3),
        ("100.0%", 100.0)
    ])
    func parsesPercent(_ line: String, _ expected: Double) {
        #expect(ProcessOutputParser.percent(from: line) == expected)
        #expect(ProcessOutputParser.progressPercent(from: line) == expected)
    }

    @Test func ignoresLinesThatAreNotProgress() {
        #expect(ProcessOutputParser.progressPercent(from: "[ExtractAudio] Destination: /a/b.mp3") == nil)
        #expect(ProcessOutputParser.progressPercent(from: "[download] Destination: /a/b.webm") == nil)
        #expect(ProcessOutputParser.progressPercent(from: "ERROR: 100% roto") == nil)
        #expect(ProcessOutputParser.percent(from: "download: N/A%") == nil)
    }

    @Test func stripsANSIAndCarriageReturns() {
        #expect(
            ProcessOutputParser.normalize("\u{1B}[0;32mdownload:  10.0%\u{1B}[0m\r\n")
                == "download:  10.0%"
        )
        #expect(ProcessOutputParser.normalize("  hola  \n") == "hola")
    }

    @Test func resolvesOutputPaths() {
        let destination = URL(fileURLWithPath: "/Users/test/Downloads", isDirectory: true)

        #expect(
            ProcessOutputParser.outputFileURL(
                from: "/Users/test/Downloads/Mi Tema.mp3",
                destination: destination
            )?.path == "/Users/test/Downloads/Mi Tema.mp3"
        )
        #expect(
            ProcessOutputParser.outputFileURL(
                from: "[ExtractAudio] Destination: /Users/test/Downloads/Mi Tema.wav",
                destination: destination
            )?.path == "/Users/test/Downloads/Mi Tema.wav"
        )
        #expect(
            ProcessOutputParser.outputFileURL(
                from: "Mi Tema.mp3",
                destination: destination
            )?.path == "/Users/test/Downloads/Mi Tema.mp3"
        )
        #expect(
            ProcessOutputParser.outputFileURL(
                from: "[download] Destination: /Users/test/Downloads/video.mp4",
                destination: destination
            ) == nil
        )
        #expect(
            ProcessOutputParser.outputFileURL(
                from: "[youtube] Extracting URL",
                destination: destination
            ) == nil
        )
    }

    @Test func detectsConversion() {
        #expect(ProcessOutputParser.indicatesConversion("[ExtractAudio] Destination: /a/b.mp3"))
        #expect(ProcessOutputParser.indicatesConversion("[ffmpeg] Post-process"))
        #expect(!ProcessOutputParser.indicatesConversion("50.0%"))
    }

    @Test func accumulatesPartialLines() {
        let accumulator = LineAccumulator()

        #expect(accumulator.append(Data("download:  1".utf8)).isEmpty)
        #expect(accumulator.append(Data("0.0%\ndownload: 20".utf8)) == ["download:  10.0%"])
        #expect(accumulator.append(Data(".0%\nready".utf8)) == ["download: 20.0%"])
        #expect(accumulator.flush() == "ready")
        #expect(accumulator.flush() == nil)
    }
}
