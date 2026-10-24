import Foundation
import Virtualization
import Darwin

@MainActor
final class Probe: NSObject, @preconcurrency VZVirtualMachineDelegate {
    let machine: VZVirtualMachine
    let input = Pipe()
    let root: URL
    let mode: String
    let began = ContinuousClock.now
    var stopping = false

    init(root: URL, mode: String) throws {
        self.root = root
        self.mode = mode
        let boot = VZLinuxBootLoader(kernelURL: root.appendingPathComponent("kernel"))
        boot.initialRamdiskURL = root.appendingPathComponent("probe.cpio.gz")
        boot.commandLine = "console=hvc0 rdinit=/init panic=5 quiet"
        let config = VZVirtualMachineConfiguration()
        config.platform = VZGenericPlatformConfiguration()
        config.cpuCount = 2
        config.memorySize = 512 * 1024 * 1024
        config.bootLoader = boot
        let console = VZVirtioConsoleDeviceSerialPortConfiguration()
        console.attachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: input.fileHandleForReading,
            fileHandleForWriting: .standardOutput)
        config.serialPorts = [console]
        try config.validate()
        precondition(config.networkDevices.isEmpty && config.directorySharingDevices.isEmpty)
        precondition(config.socketDevices.isEmpty && config.storageDevices.isEmpty)
        machine = VZVirtualMachine(configuration: config)
        super.init()
        machine.delegate = self
    }

    func start() {
        machine.start { result in
            switch result {
            case .success:
                self.emit(["event": "running", "state": self.machine.state.rawValue,
                           "network": false, "host_shares": false])
                DispatchQueue.main.asyncAfter(deadline: .now() + (self.mode == "deadline" ? 10 : 20)) {
                    self.stop(reason: "deadline")
                }
                FileHandle.standardInput.readabilityHandler = { handle in
                    let bytes = handle.availableData
                    handle.readabilityHandler = nil
                    Task { @MainActor in
                        if self.mode == "paused" {
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
        FileHandle.standardInput.readabilityHandler = nil
        guard machine.canStop else {
            emit(["event": "refused_stop", "state": machine.state.rawValue])
            exit(2)
        }
        machine.stop { error in
            if let error { self.fail(error) }
            guard self.machine.state == .stopped else { exit(3) }
            let value: [String: Any] = ["event": "stopped", "state": self.machine.state.rawValue,
                                       "reason": reason, "elapsed": "\(self.began.duration(to: .now))"]
            do {
                let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
                try data.write(to: self.root.appendingPathComponent("stop-\(self.mode).json"), options: .withoutOverwriting)
                self.emit(value)
                exit(0)
            } catch { self.fail(error) }
        }
    }

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        emit(["event": "guest_stopped", "state": virtualMachine.state.rawValue])
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
guard arguments.count == 3, ["input", "eof", "deadline", "paused", "owner_loss"].contains(arguments[2]) else { exit(64) }
let root = URL(fileURLWithPath: arguments[1], isDirectory: true)
guard canonicalPath(arguments[1]) == arguments[1], root.deletingLastPathComponent().path == "/private/tmp",
      root.lastPathComponent.hasPrefix("cuckoding-r050j-"),
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
