import Foundation
enum SharedDefaults {static let name="schedule-state-\(UUID())";static let suite=UserDefaults(suiteName:name)!;enum Keys {
 static func running(blockID:UUID)->String{"r.\(blockID)"};static func scheduleWindowStart(blockID:UUID)->String{"s.\(blockID)"};static func scheduleReleasedUntil(blockID:UUID)->String{"e.\(blockID)"}
}}
struct QAGroup { var id = UUID() }
struct BlockRule {var appGroupIDs: Set<UUID> = [];enum Kind{case schedule,tag};let id=UUID();var type:Kind = .schedule;var schedule:BlockingSchedule?;var isEnabled=false}
enum BlockResolution {static func tokens(forBlockID id:UUID)->Set<Int>?{[1]};static var blocks:[UUID:BlockRule]=[:];static func loadBlock(id:UUID)->BlockRule?{blocks[id]};static func loadGroups()->[QAGroup]?{[]};static func tokens(for block:BlockRule,groups:[QAGroup])->Set<Int>{[1]}}
enum BlockingActuator {static var shields:Set<UUID>=[];static func apply(tokens:Set<Int>,blockID:UUID){shields.insert(blockID)};static func clearShields(blockID:UUID){shields.remove(blockID)}}
enum BreakMonitoring {static var breaks:Set<UUID>=[];static var resets=0;static func resetAllowance(blockID:UUID){breaks.remove(blockID);resets+=1};static func isOnBreak(blockID:UUID)->Bool{breaks.contains(blockID)}}
@main struct Tests {
 static func main(){
  defer{SharedDefaults.suite.removePersistentDomain(forName:SharedDefaults.name)}
  let parser=ISO8601DateFormatter();let noon=parser.date(from:"2026-11-05T12:00:00Z")!;var checks=0
  func check(_ yes:Bool,_ label:String){precondition(yes,label);checks+=1}
  // Fixed UTC process timezone; actual production ScheduleEnforcement uses Calendar.current.
  var block=BlockRule(schedule:BlockingSchedule(startHour:9,endHour:17,weekdays:Set(1...7)))
  BlockResolution.blocks[block.id]=block
  ScheduleEnforcement.reconcile(block:block,now:noon)
  check(BlockingActuator.shields.contains(block.id),"in-window repair applies shield even without callback")
  let resets=BreakMonitoring.resets;BreakMonitoring.breaks.insert(block.id);BlockingActuator.shields.remove(block.id)
  ScheduleEnforcement.reconcile(block:block,now:noon.addingTimeInterval(60))
  check(!BlockingActuator.shields.contains(block.id) && BreakMonitoring.resets==resets,"same window repair respects active break")
  BreakMonitoring.breaks.remove(block.id);ScheduleEnforcement.reconcile(block:block,now:noon)
  ScheduleEnforcement.releaseCurrentWindow(block:block,now:noon);ScheduleEnforcement.reconcile(block:block,now:noon)
  check(!BlockingActuator.shields.contains(block.id),"early release preserved across callbacks")
  block.isEnabled=true;ScheduleEnforcement.reconcile(block:block,now:noon)
  check(BlockingActuator.shields.contains(block.id),"manual owner survives scheduled-window release")
  block.isEnabled=false;ScheduleEnforcement.reconcile(block:block,now:noon.addingTimeInterval(86400))
  check(BlockingActuator.shields.contains(block.id),"next window is rearmed")
  block.isEnabled=true;ScheduleEnforcement.reconcile(block:block,now:noon.addingTimeInterval(6*3600))
  check(BlockingActuator.shields.contains(block.id),"scheduled expiry preserves manual owner")
  let other=BlockRule(schedule:block.schedule);ScheduleEnforcement.reconcile(block:other,now:noon)
  block.isEnabled=false;ScheduleEnforcement.reconcile(block:block,now:noon.addingTimeInterval(6*3600))
  check(!BlockingActuator.shields.contains(block.id) && BlockingActuator.shields.contains(other.id),"release preserves independent block owner")
  print("PASS: \(checks) production schedule-state / ownership checks")
 }
}
