import Foundation
@main struct PowerModeProbe {
 static func main() {
  setbuf(stdout,nil)
  let type=BTPowerMode.getSupportedType()
  let original=BTPowerMode.readCurrent(type:type)
  print("type=\(type) baseline=\(original)")
  if CommandLine.arguments.contains("--high-check") {
   guard geteuid()==0, original.battery != nil, original.charger != nil else { exit(2) }
   print("HIGH DETECTION supported=\(BTPowerMode.checkAndSetHighPowerMode()) after=\(BTPowerMode.readCurrent(type:type))")
   return
  }
  guard CommandLine.arguments.contains("--test") else { return }
  guard geteuid()==0, let battery=original.battery, let charger=original.charger, (0...2).contains(battery), (0...2).contains(charger) else { print("ABORT"); exit(2) }
  let snapshot: [String:Any] = ["battery":battery,"charger":charger,"type":"\(type)"]
  guard (snapshot as NSDictionary).write(toFile:"/tmp/tethered-power-mode-original.plist",atomically:true) else { exit(3) }
  defer {
   let b=BTPowerMode.set(scope:.battery,mode:UInt8(battery),type:type)
   let c=BTPowerMode.set(scope:.charger,mode:UInt8(charger),type:type)
   let final=BTPowerMode.readCurrent(type:type)
   print("RESTORE writes=\(b && c) observed=\(final) verified=\(final.battery==battery && final.charger==charger)")
  }
  var passed=true
  for (scope,mode) in [(BTPowerManagementScope.battery,UInt8(1)),(.charger,1),(.battery,0),(.charger,0),(.all,1),(.all,0)] {
   let before=BTPowerMode.readCurrent(type:type)
   let accepted=BTPowerMode.set(scope:scope,mode:mode,type:type)
   let after=BTPowerMode.readCurrent(type:type)
   let match:Bool
   switch scope {
    case .battery: match=after.battery==Int(mode) && after.charger==before.charger
    case .charger: match=after.charger==Int(mode) && after.battery==before.battery
    case .all: match=after.battery==Int(mode) && after.charger==Int(mode)
    case .ups: match=false
   }
   print("scope=\(scope) mode=\(mode) accepted=\(accepted) observed=\(after) verified=\(match)")
   passed = passed && accepted && match
  }
  print("INVALID mode3 rejected=\(!BTPowerMode.set(scope:.all,mode:3,type:type)) UPS rejected=\(!BTPowerMode.set(scope:.ups,mode:0,type:type))")
  print("TRANSITIONS verified=\(passed)")
 }
}
