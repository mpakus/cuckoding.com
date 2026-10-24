import Foundation
import CryptoKit

// Test-only control decoder. No Cuckoding workflow consumes this prototype contract.
@MainActor
final class GuestCheckControl {
    let root: URL
    let mode: String
    let expected: [String: String]
    var buffer = Data()
    var transcript = Data()
    var total = 0
    var invalid = false
    var result: [String: Any]?
    var nativeStopped = false
    var cancellation: String?

    struct Report: Decodable {
        let request_id, candidate_sha, toolchain_sha256, command, stdout_sha256, stdout_base64: String
        let exit_code, stdout_bytes: Int
        let source_unchanged: Bool
    }

    init(root: URL, mode: String) throws {
        self.root = root
        self.mode = mode
        let data = try Data(contentsOf: root.appendingPathComponent("expected-checks.json"))
        guard data.count <= 8192,
              let all = try JSONSerialization.jsonObject(with: data) as? [String: [String: String]],
              let row = all[mode], Set(row.keys) == Set(["request_id", "candidate_sha", "toolchain_sha256", "command"]),
              UUID(uuidString: row["request_id"]!)?.uuidString.lowercased() == row["request_id"],
              Self.hex(row["candidate_sha"], 40), Self.hex(row["toolchain_sha256"], 64),
              ["npm test --offline", "mix test"].contains(row["command"]!) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        expected = row
    }

    func receive(_ data: Data) {
        total += data.count
        if total > 131072 { invalid = true; return }
        transcript.append(data)
        buffer.append(data)
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer[..<end]
            buffer.removeSubrange(...end)
            guard let text = String(data: line, encoding: .utf8) else { invalid = true; continue }
            if text.hasPrefix("CHECK_RESULT ") {
                guard result == nil,
                      let bytes = String(text.dropFirst(13)).data(using: .utf8),
                      let row = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], valid(row, bytes) else {
                    invalid = true
                    continue
                }
                result = row
            } else if text.trimmingCharacters(in: .whitespacesAndNewlines) == "CHECK_READY" {
                FileHandle.standardOutput.write(Data("HOST {\"event\":\"check_running\"}\n".utf8))
            }
        }
        finishIfReady()
    }

    func stopped() {
        guard !nativeStopped else { return }
        nativeStopped = true
        finishIfReady()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // A missing/invalid privileged result never becomes a passing check.
            self.retainTranscript()
            exit(5)
        }
    }

    func valid(_ row: [String: Any], _ bytes: Data) -> Bool {
        let fields = Set(["request_id", "candidate_sha", "toolchain_sha256", "command", "exit_code",
                          "stdout_sha256", "stdout_bytes", "source_unchanged", "stdout_base64"])
        guard Set(row.keys) == fields,
              let typed = try? JSONDecoder().decode(Report.self, from: bytes),
              expected.allSatisfy({ row[$0.key] as? String == $0.value }),
              (0...255).contains(typed.exit_code), (0...65536).contains(typed.stdout_bytes),
              Self.hex(row["stdout_sha256"] as? String, 64),
              let output = Data(base64Encoded: typed.stdout_base64), output.count == typed.stdout_bytes,
              SHA256.hash(data: output).map({ String(format: "%02x", $0) }).joined() == typed.stdout_sha256 else { return false }
        return true
    }

    func finishIfReady() {
        guard nativeStopped else { return }
        var row: [String: Any]
        if let cancellation {
            row = expected
            row["status"] = cancellation
        } else {
            guard !invalid, let observed = result else { return }
            row = observed
            do {
                try Data(base64Encoded: row.removeValue(forKey: "stdout_base64") as! String)!
                    .write(to: root.appendingPathComponent("output-\(mode).log"), options: .withoutOverwriting)
            } catch { exit(6) }
            row["status"] = (row["exit_code"] as? Int == 0 && row["source_unchanged"] as? Bool == true) ? "passed" : "failed"
        }
        row["contract"] = "guest-check-prototype-v1"
        row["native_state"] = 0
        row["cleanup_verified"] = true
        retainTranscript()
        do {
            let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            try data.write(to: root.appendingPathComponent("stop-\(mode).json"), options: .withoutOverwriting)
            FileHandle.standardOutput.write(Data("HOST {\"event\":\"check_closed\"}\n".utf8))
            exit(0)
        } catch { exit(6) }
    }

    func retainTranscript() {
        do {
            try transcript.write(to: root.appendingPathComponent("control-\(mode).log"), options: .withoutOverwriting)
        } catch { exit(6) }
    }

    static func hex(_ value: String?, _ count: Int) -> Bool {
        guard let value, value.utf8.count == count else { return false }
        return value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
