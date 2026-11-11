import Foundation
@main struct StateMachineQA {
 static func main() throws {
  var failures=0, checks=0
  func check(_ yes:Bool,_ label:String){checks+=1; if !yes {failures+=1};print("\(yes ? "PASS" : "FAIL"): \(label)")}
  let now=Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + 0.75)
  try AdHocMonitoring.start(group:AppGroup(),minutes:30,now:now)
  let session=AdHocMonitoring.session!
  DeviceActivityCenter().stopMonitoring([AdHocMonitoring.activityName(session.id)])
  AdHocMonitoring.reconcile(now:now.addingTimeInterval(60))
  check(DeviceActivityCenter().activities.contains(AdHocMonitoring.activityName(session.id)),"SM-03 temporary session repairs lost expiry registration")
  check(AdHocMonitoring.session?.endsAt == session.endsAt,"SM-03 repair preserves original deadline")
  DeviceActivityCenter().stopMonitoring([AdHocMonitoring.activityName(session.id)])
  AdHocMonitoring.reconcile(now:session.endsAt.addingTimeInterval(-60.25))
  let temporaryWarning=DeviceActivityCenter.schedules[AdHocMonitoring.activityName(session.id)].flatMap { schedule in
   Calendar.current.date(from:schedule.intervalEnd)?.addingTimeInterval(-Double(schedule.warningTime?.second ?? 0))
  }
  check(temporaryWarning==session.endsAt,"SM-03 fractional-time temporary repair warning is exactly at deadline")
  AdHocMonitoring.finish(id:session.id)
  // OS registration may overlap cancellation/expiry in the other process.
  DeviceActivityCenter.onStart={if let item=AdHocMonitoring.session {AdHocMonitoring.finish(id:item.id)}}
  do { try AdHocMonitoring.start(group:AppGroup(),minutes:30,now:now) } catch {}
  check(AdHocMonitoring.session == nil && State.shields.isEmpty,"SM-01 cancellation during registration cannot leave orphan temporary shield")
  if let item=AdHocMonitoring.session {AdHocMonitoring.finish(id:item.id)}
  State.shields=[]
  let id=UUID();BlockResolution.blocks[id]=BlockRule(id:id)
  SharedDefaults.suite.set(now.addingTimeInterval(-1),forKey:SharedDefaults.Keys.usageLockEnd(blockID:id))
  // Foreground repairs an absent allowance while an expiry callback is stopping its old monitor.
  DeviceActivityCenter.onStop={_ = UsageMonitoring.startUsageMonitor(forBlockID:id)}
  let before=DeviceActivityCenter.starts
  UsageMonitoring.reconcileLockout(blockID:id,now:now)
  check(DeviceActivityCenter.starts-before == 1,"SM-01 overlapping expiry/recovery arms exactly one allowance")
  let generation=UsageMonitoring.usageActivityName(for:id)
  UsageMonitoring.reconcileLockout(blockID:id,now:now)
  check(generation == UsageMonitoring.usageActivityName(for:id),"SM-01 duplicate expiry preserves allowance generation")
  // Retrying a break request cannot extend the one-break-per-activation allowance.
  let tag=UUID();BlockResolution.blocks[tag]=BlockRule(id:tag,type:.tag,isEnabled:true)
  _ = BreakMonitoring.startBreak(blockID:tag,minutes:5)
  let original=BreakMonitoring.breakEnd(blockID:tag)
  let retry=BreakMonitoring.startBreak(blockID:tag,minutes:10)
  check(!retry && BreakMonitoring.breakEnd(blockID:tag)==original,"SM-03 duplicate break request cannot extend deadline")
  DeviceActivityCenter().stopMonitoring([BreakMonitoring.breakActivityName(for:tag)])
  BreakMonitoring.finishIfExpired(blockID:tag,now:now.addingTimeInterval(60))
  check(DeviceActivityCenter().activities.contains(BreakMonitoring.breakActivityName(for:tag)) && BreakMonitoring.breakEnd(blockID:tag)==original,"SM-03 lost break re-lock is repaired without extending pause")
  let breakWarning=DeviceActivityCenter.schedules[BreakMonitoring.breakActivityName(for:tag)].flatMap { schedule in
   Calendar.current.date(from:schedule.intervalEnd)?.addingTimeInterval(-Double(schedule.warningTime?.second ?? 0))
  }
  check(breakWarning==original,"SM-03 fractional-time break repair warning is exactly at deadline")
  DeviceActivityCenter().stopMonitoring([BreakMonitoring.breakActivityName(for:tag)])
  DeviceActivityCenter.fail=true
  BreakMonitoring.finishIfExpired(blockID:tag,now:now.addingTimeInterval(60))
  check(BreakMonitoring.breakEnd(blockID:tag)==nil && State.shields.contains(tag),"SM-03 failed break repair resumes protection instead of unbounded pause")
  DeviceActivityCenter.fail=false
  BreakMonitoring.endBreak(blockID:tag,reapply:true)
  check(!BreakMonitoring.startBreak(blockID:tag,minutes:5),"SM-03 completed break cannot be taken twice in one activation")
  let inactive=UUID();BlockResolution.blocks[inactive]=BlockRule(id:inactive,type:.tag)
  check(!BreakMonitoring.startBreak(blockID:inactive,minutes:5),"SM-03 stale request cannot start break on inactive block")
  DeviceActivityCenter.schedules=[:]
  let capped=UUID();BlockResolution.blocks[capped]=BlockRule(id:capped)
  _ = UsageMonitoring.startUsageMonitor(forBlockID:capped)
  for i in 0..<19 {try DeviceActivityCenter().startMonitoring(DeviceActivityName(rawValue:"other.\(i)"),during:UsageMonitoring.allDaySchedule)}
  let old=UsageMonitoring.usageActivityName(for:capped)
  let replaced=UsageMonitoring.startUsageMonitor(forBlockID:capped)
  check(replaced && UsageMonitoring.usageActivityName(for:capped) != old && DeviceActivityCenter().activities.count==20,"SM-03 replacement at activity capacity does not fail forever")
  print("RESULT: \(checks-failures)/\(checks) state-machine checks passed")
  if failures>0 {exit(1)}
 }
}
