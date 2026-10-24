import Foundation
import Virtualization
import CryptoKit
import Darwin

enum Refusal: Error { case invalid }
func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func hex(_ value: String, _ count: Int) -> Bool {
    value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
}
func uuid(_ value: String) -> Bool { UUID(uuidString: value)?.uuidString.lowercased() == value }

// Retain descriptors through boot/shutdown; no project path is opened by this process.
final class Folder {
    let path: String
    let fd: Int32
    let identity: stat
    var held = [Int32]()
    init(_ path: String) throws {
        guard let canonical = realpath(path, nil) else { throw Refusal.invalid }
        defer { free(canonical) }
        guard String(cString: canonical) == path else { throw Refusal.invalid }
        self.path = path
        fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        var info = stat()
        guard fd >= 0, fstat(fd, &info) == 0, info.st_uid == geteuid(), info.st_mode & 0o077 == 0 else {
            if fd >= 0 { close(fd) }; throw Refusal.invalid
        }
        identity = info
    }
    deinit { for file in held { close(file) }; close(fd) }
    func current() throws {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_dev == identity.st_dev, info.st_ino == identity.st_ino,
              info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o077 == 0, info.st_uid == geteuid() else { throw Refusal.invalid }
    }
    func file(_ name: String, maximum: Int, mode: mode_t, expected: String? = nil) throws -> Data {
        let file = openat(fd, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard file >= 0 else { throw Refusal.invalid }
        var before = stat(); var after = stat()
        guard fstat(file, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_mode & 0o7777 == mode, before.st_uid == geteuid(), before.st_nlink == 1,
              before.st_size >= 0, before.st_size <= maximum else { close(file); throw Refusal.invalid }
        var bytes = Data(); var hash = SHA256(); var size = 0
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = read(file, &buffer, buffer.count)
            if count < 0 { close(file); throw Refusal.invalid }
            if count == 0 { break }
            size += count
            if size > maximum { close(file); throw Refusal.invalid }
            let chunk = Data(buffer[..<count]); hash.update(data: chunk)
            if expected == nil { bytes.append(chunk) }
        }
        guard fstat(file, &after) == 0, size == before.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { close(file); throw Refusal.invalid }
        if let expected, hash.finalize().map({ String(format: "%02x", $0) }).joined() != expected {
            close(file); throw Refusal.invalid
        }
        held.append(file)
        return bytes
    }
    func publish(_ bytes: Data, name: String = "closure.json") throws {
        try current()
        let file = openat(fd, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw Refusal.invalid }
        defer { close(file) }
        try bytes.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = write(file, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                guard count > 0 else { throw Refusal.invalid }
                offset += count
            }
        }
        guard fsync(file) == 0, fsync(fd) == 0 else { throw Refusal.invalid }
        try current()
    }
}

struct Check: Decodable, Equatable {
    let request_id, check_id, input_key, candidate_sha, manifest_sha256, image_spec_sha256: String
    let toolchain, directory: String
    let arguments: [String]
    let timeout_seconds: Int
}
struct Intent: Decodable {
    let contract, key, kernel_sha256, ramdisk_sha256, keeper_sha256, request_sha256: String
    let deadline_unix_ms: UInt64
    let check: Check
}
struct Frame: Decodable {
    let request_id, check_id, input_key, candidate_sha, manifest_sha256, image_spec_sha256: String
    let toolchain, directory: String
    let arguments: [String]
    let timeout_seconds: Int
    let contract, status, stdout_sha256, stdout_base64: String
    let stdout_bytes, observed_stdout_bytes: Int
    let exit_code: Int?
    let source_unchanged, group_closed: Bool
}

func validFrame(_ frame: Frame, _ data: Data, _ check: Check) -> Bool {
    let expected = Set(["request_id","check_id","input_key","candidate_sha","manifest_sha256","image_spec_sha256",
        "toolchain","directory","arguments","timeout_seconds","contract","status","stdout_sha256","stdout_base64",
        "stdout_bytes","observed_stdout_bytes","source_unchanged","group_closed"])
    guard let row = try? JSONSerialization.jsonObject(with:data) as? [String: Any],
          Set(row.keys) == expected.union(frame.exit_code == nil ? [] : ["exit_code"]),
          frame.request_id == check.request_id, frame.check_id == check.check_id, frame.input_key == check.input_key,
          frame.candidate_sha == check.candidate_sha, frame.manifest_sha256 == check.manifest_sha256,
          frame.image_spec_sha256 == check.image_spec_sha256, frame.toolchain == check.toolchain,
          frame.directory == check.directory, frame.arguments == check.arguments, frame.timeout_seconds == check.timeout_seconds,
          frame.contract == "guest-check-v1", frame.group_closed, (0...65536).contains(frame.stdout_bytes),
          (0...67108864).contains(frame.observed_stdout_bytes), hex(frame.stdout_sha256,64),
          let output = Data(base64Encoded:frame.stdout_base64), output.count == frame.stdout_bytes,
          digest(output) == frame.stdout_sha256,
          frame.exit_code == nil || (0...255).contains(frame.exit_code!) else { return false }
    switch frame.status {
    case "passed": return frame.source_unchanged && frame.exit_code == 0 && frame.observed_stdout_bytes == frame.stdout_bytes
    case "failed": return frame.source_unchanged && frame.exit_code != nil && frame.exit_code != 0 && frame.observed_stdout_bytes == frame.stdout_bytes
    case "source_changed": return !frame.source_unchanged && frame.observed_stdout_bytes == frame.stdout_bytes
    case "output_limit": return frame.stdout_bytes == 0 && frame.observed_stdout_bytes > 65536
    case "timeout": return frame.observed_stdout_bytes == frame.stdout_bytes
    default: return false
    }
}

@MainActor
final class Keeper: NSObject, @preconcurrency VZVirtualMachineDelegate {
    let folder: Folder
    let intent: Intent
    let intentHash: String
    let machine: VZVirtualMachine
    let console = Pipe()
    let consoleInput = Pipe()
    let began = ContinuousClock.now
    let wall = Date()
    var timer: DispatchSourceTimer?
    var buffer = Data()
    var total = 0
    var invalid = false
    var observed: Frame?
    var stopping = false
    var stoppedAt: ContinuousClock.Instant?
    var cancelReason: String?
    var startSettled = false
    var stopBegan: ContinuousClock.Instant?
    var guestRunning = false
    var runningRecorded = false

    init(_ path: String) throws {
        folder = try Folder(path)
        let bytes = try folder.file("intent.json", maximum: 32768, mode: 0o600)
        intent = try JSONDecoder().decode(Intent.self, from: bytes)
        intentHash = digest(bytes)
        let keys = Set(["contract","key","kernel_sha256","ramdisk_sha256","keeper_sha256","request_sha256","deadline_unix_ms","check"])
        guard let row = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], Set(row.keys) == keys,
              intent.contract == "isolated-guest-check-v1", uuid(intent.key),
              path.hasSuffix("/check-runs/" + intent.key),
              let home = ProcessInfo.processInfo.environment["HOME"], path == home + "/check-runs/" + intent.key,
              hex(intent.kernel_sha256,64), hex(intent.ramdisk_sha256,64), hex(intent.keeper_sha256,64) else { throw Refusal.invalid }
        let checkBytes = try folder.file("check.json", maximum: 8192, mode: 0o600)
        let requestBytes = try folder.file("request.json", maximum: 32768, mode: 0o600)
        guard hex(intent.request_sha256,64), digest(requestBytes) == intent.request_sha256 else { throw Refusal.invalid }
        guard try JSONDecoder().decode(Check.self, from: checkBytes) == intent.check else { throw Refusal.invalid }
        _ = try folder.file("kernel", maximum: 134217728, mode: 0o600, expected: intent.kernel_sha256)
        _ = try folder.file("ramdisk.cpio.gz", maximum: 201326592, mode: 0o600, expected: intent.ramdisk_sha256)
        _ = try folder.file("keeper", maximum: 16777216, mode: 0o700, expected: intent.keeper_sha256)
        guard VZVirtualMachine.isSupported else { throw Refusal.invalid }
        let boot = VZLinuxBootLoader(kernelURL: URL(fileURLWithPath:path + "/kernel"))
        boot.initialRamdiskURL = URL(fileURLWithPath:path + "/ramdisk.cpio.gz")
        boot.commandLine = "console=hvc0 rdinit=/init panic=5 quiet"
        let configuration = VZVirtualMachineConfiguration()
        configuration.platform = VZGenericPlatformConfiguration()
        configuration.cpuCount = 2
        configuration.memorySize = 1024 * 1024 * 1024
        configuration.bootLoader = boot
        let port = VZVirtioConsoleDeviceSerialPortConfiguration()
        port.attachment = VZFileHandleSerialPortAttachment(fileHandleForReading: consoleInput.fileHandleForReading,
            fileHandleForWriting: console.fileHandleForWriting)
        configuration.serialPorts = [port]
        try configuration.validate()
        guard configuration.networkDevices.isEmpty, configuration.directorySharingDevices.isEmpty,
              configuration.storageDevices.isEmpty, configuration.socketDevices.isEmpty else { throw Refusal.invalid }
        machine = VZVirtualMachine(configuration:configuration)
        super.init()
        machine.delegate = self
        for fd in [STDIN_FILENO, console.fileHandleForReading.fileDescriptor] {
            guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) == 0 else { throw Refusal.invalid }
        }
        try folder.current()
    }
    func start() {
        timer = DispatchSource.makeTimerSource(queue:.main)
        timer?.schedule(deadline:.now(), repeating:.milliseconds(20))
        timer?.setEventHandler { MainActor.assumeIsolated { self.tick() } }
        timer?.resume()
        machine.start { result in
            self.startSettled = true
            if case .failure = result { self.invalid = true; self.stop("launch_failed") }
            else if let reason = self.cancelReason { self.stop(reason) }
        }
    }
    func receive(_ data: Data) {
        total += data.count
        guard total <= 131072 else { invalid = true; stop("invalid_output"); return }
        buffer.append(data)
        while let end = buffer.firstIndex(of:10) {
            let line = Data(buffer[..<end]);buffer.removeSubrange(...end)
            guard let text = String(data:line,encoding:.utf8) else { invalid = true; continue }
            if text.hasPrefix("CC_CHECK_V1 ") {
                guard observed == nil, let json = String(text.dropFirst(12)).data(using:.utf8),
                      let frame = try? JSONDecoder().decode(Frame.self,from:json), validFrame(frame,json,intent.check) else {
                    invalid = true;continue
                }
                observed = frame
            } else if text.hasPrefix("CC_CHECK_ERROR ") { invalid = true }
            else if text.hasPrefix("CC_CHECK_RUNNING ") {
                guard !guestRunning, let json = String(text.dropFirst(17)).data(using:.utf8),
                      let row = try? JSONSerialization.jsonObject(with:json) as? [String:String],
                      row == ["request_id":intent.check.request_id,"check_id":intent.check.check_id] else {
                    invalid = true;continue
                }
                guestRunning = true
            }
        }
    }
    func tick() {
        var bytes = [UInt8](repeating:0,count:8192)
        while true {
            let count = read(console.fileHandleForReading.fileDescriptor,&bytes,bytes.count)
            if count <= 0 { break };receive(Data(bytes[..<count]))
            if total > 131072 { break }
        }
        if let stoppedAt {
            if stoppedAt.duration(to:.now) >= .milliseconds(300) { finish() }
            return
        }
        if guestRunning && startSettled && machine.state == .running && !runningRecorded {
            do {
                try folder.publish(JSONSerialization.data(withJSONObject:["key":intent.key,"native_state":machine.state.rawValue,"pid":getpid()]),name:"running.json")
                runningRecorded = true
            } catch { invalid = true;stop("invalid_output") }
        }
        let input = read(STDIN_FILENO,&bytes,1)
        if input >= 0 { stop("cancelled") }
        let elapsed = began.duration(to:.now)
        let now = Date()
        if now < wall || now.timeIntervalSince1970 * 1000 >= Double(intent.deadline_unix_ms) || elapsed >= .seconds(360) {
            stop("timeout")
        }
        if let stopBegan, stopBegan.duration(to:.now) >= .seconds(10) { exit(5) }
        if elapsed >= .seconds(370) { exit(5) }
    }
    func stop(_ reason: String) {
        guard stoppedAt == nil else { return }
        cancelReason = cancelReason ?? reason
        if stopBegan == nil { stopBegan = .now }
        guard startSettled else { return }
        if machine.state == .stopped { stopped();return }
        guard !stopping else { return }
        // Starting cannot Stop yet; the next tick retries without resetting the deadline.
        guard machine.canStop else { return }
        stopping = true
        machine.stop { error in
            guard error == nil, self.machine.state == .stopped else { exit(5) }
            self.stopped()
        }
    }
    func stopped() {
        guard machine.state == .stopped else { exit(5) }
        if stoppedAt == nil { stoppedAt = .now }
    }
    func guestDidStop(_ virtualMachine: VZVirtualMachine) { stopped() }
    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: any Error) {
        invalid = true
        if machine.state == .stopped { stopped() } else { stop("invalid_output") }
    }
    func finish() -> Never {
        guard machine.state == .stopped else { exit(5) }
        timer?.cancel();timer = nil
        var result: [String: Any] = ["contract":intent.contract,"key":intent.key,"request_id":intent.check.request_id,"check_id":intent.check.check_id,
            "input_key":intent.check.input_key,"candidate_sha":intent.check.candidate_sha,"intent_sha256":intentHash,
            "native_state":machine.state.rawValue,"vm_closed":true]
        if let cancelReason { result["status"] = cancelReason }
        else if !invalid, guestRunning, buffer.isEmpty, let frame = observed {
            result["status"] = frame.status
            result["source_unchanged"] = frame.source_unchanged
            result["stdout_bytes"] = frame.stdout_bytes
            result["observed_stdout_bytes"] = frame.observed_stdout_bytes
            result["stdout_sha256"] = frame.stdout_sha256
            if let exitCode = frame.exit_code { result["exit_code"] = exitCode }
            do { try folder.publish(Data(base64Encoded:frame.stdout_base64)!,name:"output.log") }
            catch { exit(6) }
        } else { result["status"] = "invalid_output" }
        do {
            let data = try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys])
            try folder.publish(data)
            FileHandle.standardOutput.write(data + Data([10]))
            exit(0)
        } catch { exit(6) }
    }
}

#if KEEPER_TESTS
keeperTests()
#else
guard CommandLine.arguments.count == 2 else { exit(64) }
do {
    let keeper = try Keeper(CommandLine.arguments[1])
    keeper.start()
    withExtendedLifetime(keeper) { RunLoop.main.run() }
} catch { exit(65) }

#endif
