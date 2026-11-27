# VacationQA

TSK-174 vacation mode against production `ScheduleEnforcement`, `UsageMonitoring`, `BlockingActuator`, models and `TyriMonitorExtension`, with UnreadableStoreQA's DeviceActivity/ManagedSettings doubles and a UTC clock.

Run `python3 Tests/VacationQA/run.py`. These checks don't verify real shielding, background callback delivery, or device time zone changes.
