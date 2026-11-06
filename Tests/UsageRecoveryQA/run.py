from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[2]
s=(root/'Tyri/Services/UsageLimitManager.swift').read_text();a=s.index('    func applyUsageLimit(');b=s.index('    /// Full teardown',a)
s=s[a:b];a=s.index('        #if DEBUG');b=s.index('        #endif',a)+len('        #endif');s=s[:a]+s[b:]
d='''import Foundation
struct BlockRule {enum Kind{case timer,tag};var id=UUID();var type:Kind = .timer}
enum SharedDefaults {static let suite=UserDefaults(suiteName:"usage-recovery-qa")!;enum Keys{static func usageError(blockID:UUID)->String{blockID.uuidString}}}
enum UsageMonitoring {
 static var active=false;static var measurable=true;static var starts=0;static var repairs=0;static var stops=0
 static func isUsageMonitorActive(for id:UUID)->Bool{active}
 static func usageEvent(for b:BlockRule,groups:[Int])->Int?{measurable ? 1:nil}
 static func startUsageMonitor(for b:BlockRule,groups:[Int]){starts+=1;active=true;SharedDefaults.suite.removeObject(forKey:b.id.uuidString)}
 static func stopUsageMonitor(for id:UUID){stops+=1;active=false}
 static func reconcileLockout(blockID:UUID){repairs+=1}
}
struct Probe {var locked=false;let groups:[Int]=[];var defaults:UserDefaults{SharedDefaults.suite};func lockEnd(for id:UUID)->Date?{locked ? Date().addingTimeInterval(300):nil}
METHOD
}
@main struct Tests{static func main(){
 defer{SharedDefaults.suite.removePersistentDomain(forName:"usage-recovery-qa")}
 let b=BlockRule();var p=Probe();var n=0
 func check(_ yes:Bool,_ label:String){precondition(yes,label);n+=1}
 p.applyUsageLimit(for:b,forceReset:false);check(UsageMonitoring.starts==1,"lost monitor repaired")
 p.applyUsageLimit(for:b,forceReset:false);check(UsageMonitoring.starts==1,"healthy budget retained")
 SharedDefaults.suite.set("failed",forKey:b.id.uuidString);p.applyUsageLimit(for:b,forceReset:false);check(UsageMonitoring.starts==2,"failed monitor retried")
 p.locked=true;p.applyUsageLimit(for:b,forceReset:true);check(UsageMonitoring.starts==2 && UsageMonitoring.repairs==1,"live lock repaired without new allowance")
 p.locked=false;UsageMonitoring.measurable=false;p.applyUsageLimit(for:b);check(UsageMonitoring.stops==1 && SharedDefaults.suite.string(forKey:b.id.uuidString) != nil,"empty selection stops stale monitor and reports error")
 UsageMonitoring.measurable=true;p.applyUsageLimit(for:b,forceReset:false);check(UsageMonitoring.starts==3 && SharedDefaults.suite.string(forKey:b.id.uuidString)==nil,"valid selection recovers")
 print("PASS: \\(n) production usage-manager recovery checks")
}}
'''.replace('METHOD',s)
with tempfile.TemporaryDirectory() as t:
 p=Path(t);(p/'main.swift').write_text(d)
 subprocess.run(['swiftc','-parse-as-library','-module-cache-path',str(p/'cache'),str(p/'main.swift'),'-o',str(p/'run')],check=True)
 subprocess.run([str(p/'run')],check=True)
