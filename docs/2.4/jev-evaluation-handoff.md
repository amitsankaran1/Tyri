# Tyri 2.4 — Jev evaluation workstream

User request: model the specific choices we would give Jev from user-centric input examples BEFORE choosing a tool/provider. Put an interactive HTML block in the existing Notion Tyri 2.4 task. Primary agent owns publishing the HTML. This separate Codex tab owns independent review of the choice model only.

Accepted product decisions:
- Step 1: skippable first-launch list onboarding, reusable from Lists; optional for existing users. Editable Social media, Games, Scrollers starters plus custom lists. App selections happen in Apple’s picker, not inferred tokens. Lists can overlap.
- Step 2: user describes saved lists and timing in one sentence. Editable review before saving one block. Unknown list -> list creation -> return to preserved block draft.
- Existing block types only: weekly schedule, repeating usage budget/lockout, NFC tag. No one-time dates or temporary-duration rules in this NL path. Ad hoc blocking remains a separate manual flow.
- Preserve exact durations, no preset snapping. Defaults are visible: stop early after 5-minute wait, breaks disallowed. Timer lockouts have no breaks. Schedule weekdays identify start days. All-day start=end requires explicit intent.
- Reuse account-free App Attest infrastructure. New Vercel project and Neon Free database exist. No model key currently; Amit will provide one later. No provider selected yet. Prior implementation was discarded; Notion retains historical notes, not working source.

Sources already read by primary:
https://docs.typesafe.ai/introduction
https://docs.typesafe.ai/primitives/choice
https://docs.typesafe.ai/primitives/noul
https://docs.typesafe.ai/confidence
Jev: typed Choice (one of max 255 options), Noul (yes probability), Score. Mixed questions in one request, evaluated independently in parallel. Confidence is concentration, not verified domain accuracy. Need unknown/ambiguous/unsupported handling and deterministic consistency validation.

Instructions for this tab:
1. Read the user's grill-me skill and underlying grilling instructions using Notion (URLs in session's AGENTS instructions, or 826993f193644b7fa2f4a456678dfc0e and 4073ff0a4be94fe0a84a8d1a40aa3803).
2. Independently pressure-test the finite-choice approach. Read code only as needed for facts. Do not change app/backend code, deploy, call paid model APIs, change provider, or publish Notion changes.
3. Write your findings only to docs/2.4/jev-independent-review.md. Focus on concrete question/criteria maps, multiple lists, negation, hours/minutes, usage/lockout distinction, missing-list names, ambiguity, unsupported date/temporary requests, consistency between independently evaluated questions, and a fair benchmark against Luna.
4. Primary agent is creating docs/2.4/jev-choice-model.html and will integrate your review into it and publish to Notion. Avoid editing that file. If it exists, review it as well.
5. When complete, leave a concise report visible in this tab and remain available for Amit.

Notion task: https://app.notion.com/p/40916e0e0e3a818fbe99c4af5617de8f
Project: https://app.notion.com/p/2e616e0e0e3a80148841ff8ca2cb3647
