import Foundation
import AVFoundation
import Speech
import KotoroCore
import QuantTern

// kotorocli — the command-line face of qUltraKotoro.
//
// Offline-first, like the app: emotion tagging, noise profiling, and on-device
// file/live transcription. Nothing is sent anywhere.

let argv = Array(CommandLine.arguments.dropFirst())

func stdout(_ text: String) {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(1)
}

func option(_ name: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func positional(_ args: [String]) -> [String] {
    var out: [String] = []
    var skip = false
    for a in args {
        if skip { skip = false; continue }
        if a == "--locale" || a == "--json" { skip = (a == "--locale"); continue }
        out.append(a)
    }
    return out
}

let usage = """
kotorocli — on-device speech-to-text, emotion, and noise

USAGE
  kotorocli emotion <text...> [--json]
  kotorocli noise <audio-file> [--json]
  kotorocli transcribe <audio-file> [--locale <tag>]
  kotorocli live [seconds] [--locale <tag>]
  kotorocli engines
  kotorocli locales

The QuantTern code packs a VAD emotion read into {-1, 0, +1} trits.
"""

func samples(_ buffer: AVAudioPCMBuffer) -> [Float] {
    guard let channel = buffer.floatChannelData?[0] else { return [] }
    return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
}

func json(_ pairs: [(String, String)]) -> String {
    let body = pairs.map { "\"\($0.0)\": \($0.1)" }.joined(separator: ", ")
    return "{ \(body) }"
}

@MainActor
func run() async {
    guard let command = argv.first else { stdout(usage); exit(0) }
    let rest = Array(argv.dropFirst())
    let jsonOut = argv.contains("--json")
    let localeID = option("--locale", in: argv) ?? "en-US"

    switch command {
    case "help", "-h", "--help":
        stdout(usage)

    case "engines":
        stdout("apple\tApple Speech; requires an installed on-device model. No cloud fallback.")

    case "locales":
        for l in ["en-US", "ja-JP", "zh-CN", "zh-TW", "nan-TW"] {
            stdout(l)
        }

    case "emotion":
        let text = positional(rest).joined(separator: " ")
        guard !text.isEmpty else { fail("emotion: need some text") }
        let vad = EmotionTagger().vad(for: text)
        let code = QuantTern.encode(vad)
        if jsonOut {
            stdout(json([("valence", String(vad.valence)),
                         ("arousal", String(vad.arousal)),
                         ("dominance", String(vad.dominance)),
                         ("code", "\"\(code.hex)\""),
                         ("magnitude", String(code.magnitude))]))
        } else {
            stdout(String(format: "vad   v %+.2f  a %+.2f  d %+.2f", vad.valence, vad.arousal, vad.dominance))
            stdout("code  \(code.hex)   magnitude \(code.magnitude)/3")
        }

    case "noise":
        guard let path = positional(rest).first else { fail("noise: need an audio file") }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { fail("noise: no such file: \(path)") }
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) }
        catch { fail("noise: cannot read audio: \(error.localizedDescription)") }

        guard file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)) else {
            fail("noise: cannot allocate buffer")
        }
        do { try file.read(into: buffer) }
        catch { fail("noise: read failed: \(error.localizedDescription)") }

        var detector = NoiseDetector()
        let pcm = samples(buffer)
        var index = 0
        while index < pcm.count {
            let end = min(index + 4096, pcm.count)
            detector.ingest(Array(pcm[index..<end]))
            index = end
        }
        let p = detector.profile
        if jsonOut {
            stdout(json([("levelDBFS", String(p.levelDBFS)),
                         ("peakDBFS", String(p.peakDBFS)),
                         ("zeroCrossingRate", String(p.zeroCrossingRate)),
                         ("classification", "\"\(p.classification.label)\"" )]))
        } else {
            stdout(String(format: "level  %.1f dBFS", p.levelDBFS))
            stdout(String(format: "peak   %.1f dBFS", p.peakDBFS))
            stdout(String(format: "zcr    %.3f", p.zeroCrossingRate))
            stdout("class  \(p.classification.label)")
        }

    case "transcribe":
        guard let path = positional(rest).first else { fail("transcribe: need an audio file") }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { fail("transcribe: no such file: \(path)") }
        let text: String
        do { text = try await LocalFileSpeech.transcribe(url: url, localeID: localeID) }
        catch { fail("transcribe: \(error.localizedDescription)") }
        let vad = EmotionTagger().vad(for: text)
        stdout(text.isEmpty ? "(no speech)" : text)
        stdout("code  \(QuantTern.encode(vad).hex)")

    case "live":
        let seconds = positional(rest).first.flatMap(Double.init) ?? 30
        guard seconds.isFinite && seconds > 0 && seconds <= 86400 else { fail("live: seconds must be between 0 and 86400") }
        guard LiveSpeechEngine.available(localeID: localeID) else {
            fail("live: speech recognition is unavailable for \(localeID)")
        }
        guard await LiveSpeechEngine.requestPermissions() else { fail("live: permission denied") }
        let engine = LiveSpeechEngine(localeID: localeID)
        engine.onUpdate = { update in
            let line = String(format: "[%-7@ %4.0f dB] %@", update.noise.label as NSString,
                              update.levelDBFS, update.text as NSString)
            FileHandle.standardOutput.write(Data(("\r" + line).utf8))
        }
        do { try engine.start() } catch { fail("live: \(error.localizedDescription)") }
        try? await Task.sleep(for: .seconds(seconds))
        let transcript: Transcript
        do { transcript = try await engine.stop() }
        catch { fail("live: \(error.localizedDescription)") }
        stdout("")
        stdout(transcript.text.isEmpty ? "(no speech)" : transcript.text)
        stdout(String(format: "take  %.0f s", transcript.seconds))

    default:
        fail("unknown command '\(command)'\n\n\(usage)")
    }
}

await run()
exit(0)
