import Foundation
import CoreGraphics
import Darwin

@main struct BrightnessProbe {
 @MainActor static func main() async {
  setbuf(stdout,nil)
  guard let framework=dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",RTLD_NOW), let getSymbol=dlsym(framework,"DisplayServicesGetBrightness"), let setSymbol=dlsym(framework,"DisplayServicesSetBrightness") else { print("DisplayServices unavailable"); exit(2) }
  typealias Getter = @convention(c) (UInt32,UnsafeMutablePointer<Float>) -> Int32
  typealias Setter = @convention(c) (UInt32,Float) -> Int32
  let get=unsafeBitCast(getSymbol,to:Getter.self)
  let set=unsafeBitCast(setSymbol,to:Setter.self)
  let display=CGMainDisplayID()
  var original:Float=0
  let read=get(display,&original)
  print("display=\(display) builtIn=\(CGDisplayIsBuiltin(display)) baseline_result=\(read) original=\(original)")
  guard read==0,original.isFinite,(0...1).contains(original) else { exit(3) }
  guard CommandLine.arguments.contains("--test") else { return }
  let record:[String:Any] = ["display":display,"original":original]
  guard (record as NSDictionary).write(toFile:"/tmp/tethered-brightness-original.plist",atomically:true) else { exit(4) }
  let signals=[SIGINT,SIGTERM,SIGHUP].map { value -> DispatchSourceSignal in
   signal(value,SIG_IGN)
   let source=DispatchSource.makeSignalSource(signal:value,queue:.main)
   source.setEventHandler { print("INTERRUPT restore_result=\(set(display,original))"); exit(5) }
   source.resume();return source
  }
  var passed=true
  for target in [max(0.1,original-0.0625),min(1,original+0.0625)] {
   let written=set(display,target)
   try? await Task.sleep(nanoseconds:2_000_000_000)
   var observed:Float=0
   let result=get(display,&observed)
   let verified=written==0 && result==0 && abs(observed-target)<0.01
   print("target=\(target) set_result=\(written) read_result=\(result) observed=\(observed) verified=\(verified)")
   passed = passed && verified
  }
  let restored=set(display,original)
  try? await Task.sleep(nanoseconds:2_000_000_000)
  var final:Float=0
  let finalResult=get(display,&final)
  let verified=restored==0 && finalResult==0 && abs(final-original)<0.01
  print("RESTORE set_result=\(restored) read_result=\(finalResult) observed=\(final) verified=\(verified)")
  withExtendedLifetime(signals) {}
  exit(passed && verified ? 0 : 6)
 }
}
