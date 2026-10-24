import Foundation
import Darwin

func keeperTests() {
    let check: [String: Any] = ["request_id":UUID().uuidString.lowercased(),"check_id":UUID().uuidString.lowercased(),
        "input_key":UUID().uuidString.lowercased(),"candidate_sha":String(repeating:"a",count:40),
        "manifest_sha256":String(repeating:"b",count:64),"image_spec_sha256":String(repeating:"c",count:64),
        "toolchain":"npm","directory":".","arguments":["test","--offline"],"timeout_seconds":20]
    let typed = try! JSONDecoder().decode(Check.self,from:JSONSerialization.data(withJSONObject:check))
    var frame = check
    for (key,value) in ["contract":"guest-check-v1","status":"passed","stdout_sha256":digest(Data("abc".utf8)),
                        "stdout_base64":Data("abc".utf8).base64EncodedString()] { frame[key] = value }
    frame["stdout_bytes"] = 3;frame["observed_stdout_bytes"] = 3;frame["source_unchanged"] = true
    frame["group_closed"] = true;frame["exit_code"] = 0
    func valid(_ row: [String: Any]) -> Bool {
        let data = try! JSONSerialization.data(withJSONObject:row)
        guard let decoded = try? JSONDecoder().decode(Frame.self,from:data) else { return false }
        return validFrame(decoded,data,typed)
    }
    precondition(valid(frame))
    for (field,value) in [("request_id",UUID().uuidString.lowercased() as Any),("toolchain","sh" as Any),
        ("group_closed",false),("source_unchanged",false),("stdout_bytes",true),("stdout_bytes",65537),
        ("stdout_base64","forged"),("stdout_sha256",String(repeating:"0",count:64)),("raw","canary"),("exit_code",1)] {
        var changed = frame;changed[field]=value;precondition(!valid(changed),field)
    }
    var timeout = check
    timeout.merge(["contract":"guest-check-v1","status":"timeout","source_unchanged":true,"group_closed":true,
        "stdout_bytes":0,"observed_stdout_bytes":0,"stdout_sha256":digest(Data()),"stdout_base64":""]) {_,new in new}
    precondition(valid(timeout));precondition(timeout["exit_code"] == nil)
    var partial = frame;partial.removeValue(forKey:"stdout_bytes");precondition(!valid(partial))
    let directory = URL(fileURLWithPath:"/private/tmp",isDirectory:true).appendingPathComponent("cuckoding-keeper-unit-"+UUID().uuidString.lowercased())
    try! FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    let folder = try! Folder(directory.path)
    try! Data("data".utf8).write(to:directory.appendingPathComponent("file"),options:.withoutOverwriting)
    try! FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:directory.path+"/file")
    precondition(try! folder.file("file",maximum:4,mode:0o600)==Data("data".utf8))
    try! FileManager.default.createSymbolicLink(atPath:directory.path+"/link",withDestinationPath:directory.path+"/file")
    do { _ = try folder.file("link",maximum:4,mode:0o600);preconditionFailure() } catch {}
    do { _ = try folder.file("file",maximum:3,mode:0o600);preconditionFailure() } catch {}
    try! folder.publish(Data("{}".utf8))
    do { try folder.publish(Data("overwrite".utf8));preconditionFailure() } catch {}
    print("PASS: keeper exact frame validation and private descriptor/receipt checks; no VM.")
}
