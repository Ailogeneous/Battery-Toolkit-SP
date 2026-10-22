import Foundation
@main struct FanProbe {
 @MainActor static func main() async {
  setbuf(stdout, nil)
  guard SMCComm.start() else { print("SMC open failed"); exit(2) }
  func show(_ stage: String) { print(stage); for fan in BTFanControl.getFans() { print(fan) } }
  show("BASELINE")
  if CommandLine.arguments.contains("--reset-check") {
   print("RESET CHECK",BTFanControl.resetFanControlNow().rawValue)
   show("AFTER RESET CHECK")
   return
  }
  guard CommandLine.arguments.contains("--test") else { return }
  guard geteuid() == 0 else { print("Test requires root"); exit(2) }
  let baseline = BTFanControl.getFans()
  guard baseline.count == 2, baseline.allSatisfy({ ($0["mode"] as? NSNumber)?.intValue != 1 }) else { print("ABORT: existing manual control must not be disturbed"); exit(3) }
  var names = ["F0Md", "F1Md", "F0Tg", "F1Tg"]
  if SMCComm.getKeyInfo(key: SMCComm.Key("F","t","s","t")) != nil { names.append("Ftst") }
  var saved: [(SMCComm.Key, [UInt8])] = []
  for name in names {
   let c = Array(name); let key = SMCComm.Key(c[0],c[1],c[2],c[3])
   guard let info = SMCComm.getKeyInfo(key:key), let bytes=SMCComm.readKey(key:key,dataSize:Int(info.dataSize)) else { print("snapshot failed",name); exit(5) }
   saved.append((key,bytes))
  }
  func restoreExact() -> Bool {
   _ = BTFanControl.resetFanControlNow()
   var ok = true
   for (key,bytes) in saved { ok = SMCComm.writeKey(key:key,bytes:bytes) && ok }
   for (key,bytes) in saved { ok = SMCComm.readKey(key:key,dataSize:bytes.count) == bytes && ok }
   return ok
  }
  let signals = [SIGINT,SIGTERM,SIGHUP].map { value -> DispatchSourceSignal in
   signal(value,SIG_IGN)
   let source=DispatchSource.makeSignalSource(signal:value,queue:.main)
   source.setEventHandler { MainActor.assumeIsolated { print("INTERRUPT RESTORE",restoreExact()); exit(4) } }
   source.resume(); return source
  }
  let result = await BTFanControl.setFanControlLease(percent: 65, durationSeconds: 30)
  print("LEASE result=",result.rawValue)
  for _ in 0..<8 { try? await Task.sleep(nanoseconds: 5_000_000_000); show("OBSERVE \(Date())") }
  print("FINAL RESET",BTFanControl.resetFanControlNow().rawValue)
  print("EXACT ORIGINAL RESTORE",restoreExact())
  show("RESTORED")
  withExtendedLifetime(signals) {}
  SMCComm.stop()
 }
}
