# Papercut fixes — TestFlight 2.3 (8)

- Timed lockouts show their end time in Focus and details. An independent manual Block now override is disclosed instead of promising automatic release; early-stop messaging no longer replaces the timed end.
- List Save validates and includes the pending website without requiring the + button. Invalid input stays editable with an inline explanation.
- HTTP(S) URLs normalize to validated DNS hosts, excluding paths, queries, fragments and ports. Credentials, unsupported schemes, malformed labels and invalid ports are rejected.
- Schedule registration failures are retained per block and shown in Focus and the editor with Retry schedule. Save retains the saved editor on failure. Success for a different block does not erase the failure.

Validation: 25 domain/status checks, eight production schedule-manager checks with OS doubles, 12 lifecycle checks and 16 calendar checks passed. Focused simulator UI coverage checks timed status, invalid website feedback, Save without +, persistence after relaunch, and schedule failure/retry. The initial schedule UI test expected Save to dismiss on failure; updated to acknowledge the new error behavior before checking persistence.

This changes presentation and input validation, not enforcement rules or usage measurement. Physical Screen Time enforcement is not verified by simulator tests. Live numeric usage remains unfinished. The original Circuit Breaker report did not include persisted manual/lockout state, so its exact on-device state was not reproduced; timed and mixed manual/timed cases are handled explicitly.

Final result: all three focused simulator scenarios passed. The schedule retry selector was also narrowed to the visible editor because Focus exposes its own Retry schedule button. Evidence: `/tmp/tyri-build8-ui.xcresult` and `/tmp/tyri-build8-schedule-final.xcresult`. Actual screenshots are attached at the top of the Tyri Notion page. TestFlight 2.3 (8) uploaded successfully; Apple processing and tester availability are not yet verified.
