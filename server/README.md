# Tyri interpretation service

Provider-neutral restoration for 2.4. POST /api/challenge and /api/enroll implement account-free App Attest. /api/create verifies a request-bound assertion; it returns `provider_unconfigured` until an evaluated extractor is selected. No model key is embedded in the app or this repository. No live interpretation is claimed.

Dedicated Vercel project: `tyri-creation-api`, personal team `amitsankaran1s-projects`. Dedicated Neon Free resource: `tyri-creation-attestation`. Credentials are injected by the integration; `.env.local` is ignored and mode 0600.

Run `node --env-file=.env.local migrate.mjs` against the dedicated database, and `npm test`. Tests label generated-key fixtures and store/verifier doubles. Production allows TestFlight/App Store categories when authenticated extensions are supplied; legacy extension-free assertions remain supported. The AT flag on a short assertion header is accepted without altering signed bytes, preserving the prior device fix.

One-use 5-minute challenges bind key, environment and purpose. Enrollment retries accept only the exact original body and cannot reset a counter. Database transactions consume a challenge, advance a counter and reserve budgets together. Limits: 30 model requests/device/day, 500 globally/day, 120 challenge requests/IP/hour, 3000 challenges globally/day. Bodies are bounded to 24 KiB. IP budget keys are daily hashes, removed after two days; challenge records expire and are purged after an additional hour. Device verification keys and receipts remain until explicit resource/device cleanup. No user request text or app selections are stored.

Physical-device acceptance remains required for real Apple enrollment/assertions. Generated signing keys do not establish successful Apple attestation. Model selection, its secret, interpretation benchmarks, and provider adapter are pending the choice-model review in Notion.
