import Foundation
import Virtualization
import Darwin

@MainActor
final class Probe: NSObject, @preconcurrency VZVirtualMachineDelegate {
    let machine: VZVirtualMachine
    let input = Pipe()
    let output = Pipe()
    let check: GuestCheckControl?
    let root: URL
    let mode: String
    let began = ContinuousClock.now
    var stopping = false

    init(root: URL, mode: String) throws {
        self.root = root
        self.mode = mode
        check = mode.hasPrefix("check_") ? try GuestCheckControl(root: root, mode: mode) : nil
        let boot = VZLinuxBootLoader(kernelURL: root.appendingPathComponent("kernel"))
        boot.initialRamdiskURL = root.appendingPathComponent("probe.cpio.gz")
        boot.commandLine = "console=hvc0 rdinit=/init panic=5 quiet" +
            (mode == "watchdog_memory" ? " cc_probe=memory" : "") +
            (check != nil ? " cc_check=\(mode)" : "")
        let config = VZVirtualMachineConfiguration()
        config.platform = VZGenericPlatformConfiguration()
        config.cpuCount = 2
        config.memorySize = (check != nil ? 1024 : 512) * 1024 * 1024
        config.bootLoader = boot
        let console = VZVirtioConsoleDeviceSerialPortConfiguration()
        console.attachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: input.fileHandleForReading,
            fileHandleForWriting: check != nil ? output.fileHandleForWriting : .standardOutput)
        config.serialPorts = [console]
        try config.validate()
        precondition(config.networkDevices.isEmpty && config.directorySharingDevices.isEmpty)
        precondition(config.socketDevices.isEmpty && config.storageDevices.isEmpty)
        machine = VZVirtualMachine(configuration: config)
        super.init()
        machine.delegate = self
        if check != nil {
            output.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                DispatchQueue.main.async { self.check?.receive(data) }
            }
        }
    }

    func start() {
        machine.start { result in
            switch result {
            case .success:
                self.emit(["event": "running", "state": self.machine.state.rawValue,
                           "network": false, "host_shares": false])
                DispatchQueue.main.asyncAfter(deadline: .now() + (self.check != nil ? 40 : self.mode == "deadline" ? 10 : 20)) {
                    self.stop(reason: "deadline")
                }
                FileHandle.standardInput.readabilityHandler = { handle in
                    let bytes = handle.availableData
                    handle.readabilityHandler = nil
                    Task { @MainActor in
                        if self.mode.hasPrefix("watchdog_") {
                            self.emit(["event": "controller_lost", "guest_watchdog": true])
                        } else if self.mode == "paused" {
                            self.machine.pause { result in
                                switch result {
                                case .success:
                                    self.emit(["event": "paused", "state": self.machine.state.rawValue])
                                    self.stop(reason: "paused_controller")
                                case .failure(let error): self.fail(error)
                                }
                            }
                        } else {
                            self.stop(reason: bytes.isEmpty ? "controller_eof" : "controller_input")
                        }
                    }
                }
            case .failure(let error):
                self.fail(error)
            }
        }
    }

    func stop(reason: String) {
        guard !stopping else { return }
        stopping = true
        check?.cancellation = reason == "deadline" ? "timeout" : "cancelled"
        FileHandle.standardInput.readabilityHandler = nil
        guard machine.canStop else {
            emit(["event": "refused_stop", "state": machine.state.rawValue])
            exit(2)
        }
        machine.stop { error in
            if let error { self.fail(error) }
            self.recordStop(reason: reason)
        }
    }

    func recordStop(reason: String) {
        guard machine.state == .stopped else { exit(3) }
        if let check {
            check.stopped()
            return
        }
        let value: [String: Any] = ["event": "stopped", "state": machine.state.rawValue,
                                   "reason": reason, "elapsed": "\(began.duration(to: .now))"]
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            try data.write(to: root.appendingPathComponent("stop-\(mode).json"), options: .withoutOverwriting)
            emit(value)
            exit(0)
        } catch { fail(error) }
    }

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        emit(["event": "guest_stopped", "state": virtualMachine.state.rawValue])
        if let check {
            guard machine.state == .stopped else { exit(3) }
            check.stopped()
            return
        }
        if mode.hasPrefix("watchdog_") && !stopping { recordStop(reason: "guest_shutdown") }
        if !stopping { exit(4) }
    }

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: any Error) {
        fail(error)
    }

    func fail(_ error: any Error) -> Never {
        let error = error as NSError
        emit(["event": "failed", "domain": error.domain, "code": error.code])
        exit(1)
    }

    func emit(_ value: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        FileHandle.standardOutput.write(Data("HOST ".utf8) + data + Data([10]))
    }
}

func canonicalPath(_ path: String) -> String? {
    guard let pointer = realpath(path, nil) else { return nil }
    defer { free(pointer) }
    return String(cString: pointer)
}

let arguments = CommandLine.arguments
guard arguments.count == 3, ["input", "eof", "deadline", "paused", "owner_loss", "watchdog_pids",
    "watchdog_memory", "watchdog_eof", "watchdog_owner_loss", "check_npm_pass", "check_npm_fail",
    "check_mix_pass", "check_mix_fail", "check_forgery", "check_source_mutation", "check_output_boundary", "check_output_limit",
    "check_cancel", "check_owner_loss"].contains(arguments[2]) else { exit(64) }
let root = URL(fileURLWithPath: arguments[1], isDirectory: true)
guard canonicalPath(arguments[1]) == arguments[1], root.deletingLastPathComponent().path == "/private/tmp",
      ["cuckoding-r050j-", "cuckoding-r050k-", "cuckoding-r050l-"].contains(where: root.lastPathComponent.hasPrefix),
      root.path == arguments[1] else { exit(65) }
guard VZVirtualMachine.isSupported else { exit(66) }
do {
    let probe = try Probe(root: root, mode: arguments[2])
    probe.start()
    withExtendedLifetime(probe) { RunLoop.main.run() }
} catch {
    let error = error as NSError
    print("HOST failure domain=\(error.domain) code=\(error.code)")
    exit(1)
}
