import Foundation
var passed = 0
func expect(_ title: String, valid: Bool, _ draft: BlockDescriptionDraft) {
    do { try draft.validate(); precondition(valid, "Unexpectedly accepted: \(title)") }
    catch { precondition(!valid, "Unexpectedly rejected: \(title): \(error)") }
    passed += 1
}
let weekly = BlockDescriptionDraft(name:"Work", lists:[.init(existingID:"00000000-0000-4000-8000-000000000001",name:"Social media")], type:"schedule", schedule:.init(weekdays:[2,3,4,5,6],startMinute:555,endMinute:1000,allDay:false), usageMinutes:nil, lockoutMinutes:nil, cooldownMinutes:nil,breakMinutes:nil,clarification:nil,unsupportedReason:nil)
expect("exact 09:15–16:40",valid:true,weekly)
var d=weekly;d.schedule!.startMinute=1320;d.schedule!.endMinute=120;expect("overnight",valid:true,d)
d=weekly;d.schedule!.endMinute=555;expect("equal clocks require explicit all day",valid:false,d)
d.schedule!.allDay=true;expect("explicit 24-hour window",valid:true,d)
d=weekly;d.schedule!.weekdays=[];expect("missing days",valid:false,d)
d=weekly;d.schedule!.weekdays=[0,8];expect("invalid days",valid:false,d)
d=weekly;d.schedule!.weekdays=[2,2];expect("duplicate days",valid:false,d)
d=weekly;d.schedule!.endMinute=560;expect("too short OS interval",valid:false,d)
d=weekly;d.schedule!.startMinute=1440;expect("invalid clock",valid:false,d)
d=weekly;d.clarification="AM or PM?";expect("unresolved ambiguity",valid:false,d)
d=weekly;d.unsupportedReason="One-time dates are unsupported";expect("unsupported requirement",valid:false,d)
d=weekly;d.lists=[];expect("no targets",valid:false,d)
d=weekly;d.name="  ";expect("blank name",valid:false,d)
d=weekly;d.type="admin";expect("unknown mode",valid:false,d)
d=weekly;d.usageMinutes=30;expect("inconsistent mode fields",valid:false,d)
d=weekly;d.type="timer";d.schedule=nil;d.usageMinutes=40;d.lockoutMinutes=50;expect("exact usage 40/50",valid:true,d)
d.lockoutMinutes=nil;expect("missing lockout",valid:false,d)
d.lockoutMinutes=5;expect("five minute lockout",valid:true,d)
d.usageMinutes=5;expect("five minute allowance",valid:true,d)
d.usageMinutes=1435;d.lockoutMinutes=1435;expect("maximum duration",valid:true,d)
d.lockoutMinutes=1440;expect("over maximum",valid:false,d)
d.lockoutMinutes=7;expect("not five minute steps",valid:false,d)
d.lockoutMinutes=50;d.breakMinutes=10;expect("timer cannot break",valid:false,d)
d.breakMinutes=0;d.usageMinutes=0;expect("zero usage",valid:false,d)
d=weekly;d.type="tag";d.schedule=nil;expect("NFC",valid:true,d)
d.cooldownMinutes=0;expect("no early stop",valid:true,d)
d.breakMinutes=61;expect("invalid access duration",valid:false,d)
print("PASS: \(passed) description validation checks")
