# Jev feasibility from the list → schedule journey

Reviewed 2026-11-04. Design review, not model-performance evidence. No application/backend changes or model calls. Amit subsequently authorized publishing this review artifact directly to the existing Notion task.

## Finding

**The intended journey does not inherently require a generative LLM. Jev is a plausible interpreter for saved-list membership, weekly days, exact clock components, and supported rule types. List creation itself is a user action with a name field and Apple's picker.** The unresolved issue is how much free-form extraction the sentence must perform before that screen opens.

Do not equate “arbitrary exact time” with “requires text generation”: hours and minutes are finite. Do not equate “a missing list exists” with “we have recovered its name”: classification and extracting a new string are different capabilities.

Recommended evaluation: keep the agreed journey and compare Jev plus deterministic handling against Luna on the same sentences and review behavior. Do not choose a provider yet. Prefer clear-name prefill when available, with an editable name field when uncertain. That prefill may come from a deterministic source-span candidate, so it does not by itself require an LLM. Arbitrary language coverage would make an LLM extractor more attractive; only measured completion and correction burden can settle that trade-off.

## User journey first

| Step | What the person sees and does | Information established | Does this require Jev or an LLM? |
| --- | --- | --- | --- |
| 1. First launch or Lists | Build lists now, or skip. Existing users can opt in. | Whether to configure reusable lists now | Neither; explicit UI choice |
| 2. Pick a starting point | Social media, Games, Scrollers, or custom; starters can be renamed | Proposed list name, not app membership | Neither; starter text or user input |
| 3. Choose contents | Open Apple's picker and select apps/categories; review the selection | Actual local blocking selection | Neither model can choose native tokens by app name |
| 4. Save list | Confirm name and contents; repeat or finish | Stable local list ID and user-controlled name | Neither; deterministic validation and persistence |
| 5. Describe one block | “Block Social media and Games weekdays 9:15am–5:40pm” | Candidate target lists and timing | Jev can classify bounded decisions below; LLM is another candidate |
| 6. Resolve list references | Reuse matching lists; choose between ambiguous names; create missing lists | Every target refers to a real saved list | Jev can select known references; unknown names need input or extraction |
| 7. Create missing list | Preserve sentence and timing, show editable name, open picker, save, return | New stable ID attached to the original draft | Same list editor as steps 2–4; no second interpretation needed merely because an ID was created |
| 8. Resolve timing | Clarify missing days, AM/PM, end time, or conflicting clauses | One valid weekly window shared by all targets | Jev proposes; targeted controls supply unresolved values |
| 9. Review and save | Named lists, days, exact times, overnight ending day, early-stop and break settings | User-approved schedule | Local validation and explicit save; no model decides activation |

Creating a list does not start blocking. Lists may overlap. If list creation succeeds but schedule creation is cancelled, make it clear that the list remains saved; list save and block save are separate actions. Cancelling a picker or list editor must preserve the original schedule draft and leave that reference unresolved. With two missing lists, resolve both without losing the first one. Handle permission denial in the list editor, not as a model interpretation failure.

## Discrete decisions needed for schedule review

These are proposed semantic contracts, not claims about observed Jev answers. Every question must include its meaning in the instructions: TypeSafe does not expose the question ID to the model. All questions receive the same sentence and saved-list snapshot.

| Decision / question | Discrete choices or criteria | Local composition and review consequence |
| --- | --- | --- |
| Rule intent: “Which behavior is requested?” | weekly schedule; usage cycle; NFC; multiple rules; unclear; not a creation request | Route to the correct editor. Do not classify any sentence containing minutes as a usage cycle. |
| Scope supported: “Is an explicit requirement outside this version?” | none; one-time date; immediate duration; daily cap; separate windows/rules; app subtraction; other; uncertain | Never discard an unsupported clause to salvage a weekly draft. Multiple reasons can be separate checks if needed. |
| List scope | named lists; all current saved lists; all current except named; missing; ambiguous | Snapshot concrete IDs; “all lists” does not mean all installed apps or future lists. |
| Per saved list: “Is this list a target?” | include = requested target; exclude = explicitly omitted; unmentioned; ambiguous | One question per list permits several targets. Stable IDs are resolved locally. Do not enumerate every subset. |
| Unresolved reference | none; at least one absent list; ambiguous existing match | This detects a creation detour; it does not supply an arbitrary new name. |
| Per missing-name candidate | exact source span is a requested list name; not a name; ambiguous | Optional candidate-selection design. Candidate generation must be specified and tested; no invented name. Otherwise show a name field. |
| Per day: “Does this window START on Monday?” (repeat for seven days) | yes; no; unspecified; contradictory/ambiguous | Weekdays except Friday → Mon–Thu. Friday 22:00–02:00 starts Friday, ends Saturday. |
| Start/end availability (separate questions) | explicit; missing; ambiguous; not applicable | Missing/ambiguous values require controls. They must not become zero. |
| Start/end clock components | hour 0–23 plus unknown; minute 0–59 plus unknown | Compose 60 × hour + minute. 9:15am and 5:40pm → 555 and 1060. No preset rounding. |
| All-day intent | explicit full day; no; ambiguous | Only explicit all-day intent may produce equal start/end; use a deterministic midnight convention for “all Saturday.” |
| Time-zone requirement | device local; explicit other zone; ambiguous | Show local-time behavior. Do not silently discard “London time.” |
| Stop early | omitted; disallowed; explicit wait; ambiguous | Omitted visibly uses 5-minute wait; disallowed maps to no early-stop path, not instantaneous unlock. |
| Breaks | omitted; disallowed; one specified duration; unsupported policy; ambiguous | Default visibly disallows breaks. Usage lockouts cannot have breaks. |

The person should see a compact review, not these model questions. Group it as **Lists → Days → Start/end → Access settings**, exposing only the unresolved controls. No confidence percentage substitutes for this review.

## Three list paths that determine feasibility

**Saved lists:** “Block Social media and Games weekdays 9am–5pm.” Jev can select include/include/unmentioned for the three starters and finite timing values. No new text is necessary. Name the block deterministically or let the user name it; do not add a generation requirement just for a decorative title.

**Custom list created first:** The person names a list “Rabbit holes,” chooses apps, then says “Block Rabbit holes weekdays 9am–5pm.” The unusual name is now a supplied option. Free-form naming in a text field is not a reason to use an LLM.

**Missing list mentioned in the sentence:** “Block Shopping and News weekdays 9am–5pm.” Jev can detect an absent reference. It can also select Shopping/News if a local extractor has already supplied those spans as candidates. It cannot directly return unconstrained new names through a Choice. Preserve the draft, confirm each name and picker selection, bind each saved ID, then review the original timing. A detector that only returns `unknown_list=yes` is insufficient to present two named creation actions.

The hard examples are names that look like timing or operators: “After Hours,” “Games and More,” “Not Work,” and two saved lists both called “Social.” Avoid splitting on every “and,” treating every “not” as negation, or guessing which duplicate ID was intended. Candidate extraction and duplicate disambiguation are part of the evaluated pipeline, not free preprocessing.

## What finite output can and cannot establish

TypeSafe Choice selects one of up to 255 supplied options. Its option names/descriptions are visible; question IDs are not. Therefore per-list membership and component times fit the interface. A single choice over every possible minute of the day would exceed that bound; splitting hour/minute is one representable alternative. [Choice documentation](https://docs.typesafe.ai/primitives/choice)

Jev evaluates mixed questions independently against the same state. An answer to “rule intent” does not condition another question in that same call. Include applicability criteria in each question, then gate the results in code. [Introduction](https://docs.typesafe.ai/introduction)

Noul supplies a probability for a yes/no proposition. A middling result is not “not mentioned.” Prefer explicit multiway choices where missing, excluded and ambiguous must remain distinct, or define separate presence and ambiguity checks. [Noul documentation](https://docs.typesafe.ai/primitives/noul)

Confidence summarizes concentration of the output distribution; it is not evidence that a Tyri schedule is correct. Thresholds must be selected on development data and evaluated on unseen cases. [Confidence documentation](https://docs.typesafe.ai/confidence)

Jev plus code can, in principle, recover text through bounded span choices or multiple stages. It would be inaccurate to claim that an LLM is mathematically necessary for every new name. The practical questions are candidate coverage, ambiguity, request size, extra calls, and how often the user must repair the result.

## Independent failure checks

| User input / condition | Required behavior |
| --- | --- |
| “Block Social media, not Games, weekdays 9am–5pm” | Omit the Games list. Do not promise every Games app is available: overlap with Social media can still block it. Clarify if the user intends an app-level exception. |
| “Games on weekends, Social media on weekdays” | Do not merge targets and days into one block. Explain separate blocks are needed. |
| “Weekdays except Friday, 9am–5pm” | All five weekday classifiers must respect the exception; validate the composed day set. |
| “Every weekday, but never weekdays” | Clarify contradiction; no silent empty schedule or arbitrary winner. |
| “9 to 11,” “after dinner,” or “weekend nights” | Ask targeted time/start-day questions; never infer lifestyle or business-hour defaults. |
| “All day Saturday” | Explicit full day; Saturday 00:00 → Sunday 00:00. A rule requiring literal start/end text must special-case this. |
| “9am–9am” without full-day intent | Clarify; equal values alone cannot authorize 24-hour blocking. |
| “Tomorrow 9am–11am” / “for the next hour” | Unsupported in this NL path. Do not convert to repeating weekday or permanent toggle. |
| “Allow 40 minutes, then block 50 minutes” | Usage=40, lockout=50, exact. It is not a weekly schedule. |
| “After 90 minutes of use, block for an hour and a half” | Normalize both to 90; ensure component answers agree with the same phrase. |
| “Block for 50 minutes after 40 minutes of use” | Usage=40, lockout=50 despite reversed surface order. |
| “30 minutes per day” | Do not turn a daily cap into a repeating usage/lockout cycle. |
| List is renamed/deleted while draft is open | Revalidate IDs and contents before save; do not silently select a replacement. |

Independent answers can form a syntactically valid wrong schedule. Bounds checks cannot detect every swapped time, wrong list, or misread exception. Require one supported rule, resolved nonempty target set, coherent day/time/all-day values, correct type-specific fields, known IDs, permitted durations and access settings. Compare numeric fields with deterministic parsed spans when available. Contradictions and uncertainty require clarification, not whichever answer has the largest confidence.

## Review of the parallel choice-model draft

At inspection, `jev-model-data.json` and `build-jev-model.py` existed; `jev-choice-model.html` was not yet present. The catalog already handles plural lists, missing/ambiguous states, exact clock components and unsupported dates well. The following additions matter to the journey:

1. Expand `unknown_list` into the full name-confirmation → native picker → saved ID → preserved schedule return path. An example displaying “Create Shopping” must identify where that name came from.
2. Qualify the “all lists except Games” example: excluding a list does not subtract shared apps from other included lists.
3. Avoid gating all-day on start/end being literally explicit; derive midnight bounds only after explicit all-day intent is established.
4. Mark component duration normalization as an untested model task. Independent 90-minute answers could combine into 60 or 120 despite valid ranges.
5. Demonstrate cancellation, two missing lists, ambiguous names and permission denial alongside the happy path. Show which actions are user decisions and which are proposed Jev answers.

## Fair Jev versus Luna evaluation

No live benchmark was run. At the initial review, Luna was the candidate named in the handoff without a verified API model. The follow-up below verifies the documented `gpt-6-luna` candidate; project access and actual performance remain untested. No provider has been selected.

Use one frozen, human-labeled corpus with the same saved-list snapshots, original sentences, accepted defaults, unsupported behaviors, review editor and validator. Compare (A) Jev with direct component choices, (B) Jev plus a documented local candidate parser, and (C) Luna with structured draft extraction. Include a deterministic-only baseline for explicit-name/time inputs. Report preprocessing and fallback work for every pipeline.

Stratify cases across existing lists, new lists, mixed existing/new, two missing names, duplicate/near-match names, overlap and negation, exact/overnight/all-day times, vague language, unsupported requests, usage/lockout roles and contradictory clauses. Hold out whole paraphrase families from prompt/threshold tuning. Label expected disposition as review, clarify, create list, or unsupported as well as expected fields.

Measure complete-draft semantic match; silent wrong-block rate; correct clarification and unnecessary clarification; list-name recovery; user corrections and extra actions; completion without retyping; abandonment in a small observed UX test; end-to-end latency including extra calls; and total cost per successful reviewed draft. Do not compare Jev field accuracy with Luna whole-plan accuracy. Do not count every abstention as a success.

Recommendation: retain Jev if it satisfies the same UX with acceptable correction burden and lower measured operational cost/latency. Prefer an LLM if free-form extraction materially improves successful completion enough to justify it. A hybrid only earns its complexity through that comparison. Zero severe semantic errors on a release corpus is a proposed gate, not proof of zero production risk.

## Decision frontier

The accepted onboarding, picker, one-block scope and exact-time decisions remain settled. Amit confirmed: **label the list when clear, and make it obvious that users must select the apps themselves first.** Therefore the missing-list screen should say, for example, “Shopping — choose apps to finish this list,” with an editable name and a prominent “Choose apps” action. A recognized name is not a configured list. Require the user's contents selection before completing the list and continuing to schedule review. When the name is unclear, ask for it; do not invent one. No further product decision is required to publish this review; Jev accuracy and candidate extraction remain empirical evaluation work.

## Luna and combined pipelines — UX comparison

Follow-up requested by Amit: model Luna and Jev together to find the best experience. This expands the design comparison; it does not select or implement a provider.

### Recommendation to test

**Use Luna alone as the reference experience; test Luna plus a selective Jev semantic check as the quality challenger.** Keep Jev-only and Jev-first/Luna-fallback in the benchmark. This is an architectural recommendation, not a measured ranking. Prefer one model unless adding the second demonstrably reduces wrong drafts without introducing excessive questions or delay.

The person should encounter the same flow with every pipeline: describe → resolve genuine missing information → choose apps for new lists → review → save. Model names, routing, confidence scores and internal disagreement do not belong in that product flow. Preserve the accepted name-first, explicit app-selection behavior.

### Current Luna capability and illustrative cost

Official documentation identifies `gpt-6-luna`, supports Structured Outputs and the Responses API, and lists standard token rates of $0.10/million input and $0.50/million output. This establishes an API candidate, not verified access for this project or Tyri accuracy. [GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna)

Illustrative arithmetic: 2,000 input + 500 total billed output tokens costs $0.00045 per request, or $4.50 per 10,000 requests at those rates. This is not a measured Tyri request size or complete operating cost; account for reasoning tokens, retries, optional calls, backend costs and applicable pricing modifiers. At this illustrative scale, avoid sacrificing UX merely to reduce token cost. No model API was invoked or credentials configured for this comparison.

Structured output constrains shape, not meaning; errors and incompatible input still need handling. [Structured Outputs guidance](https://developers.openai.com/api/docs/guides/structured-outputs)

### Four concrete pipelines

| Pipeline | Processing before the same review | Potential user benefit | Cost or failure mode to measure |
| --- | --- | --- | --- |
| Jev + deterministic parser | Candidate names/times → discrete Jev questions → compose and validate | Precise bounded classifications; straightforward saved-list cases | Candidate gaps can require extra user naming; components can disagree; no measured speed advantage assumed |
| Luna alone | One structured extraction of names, references, timing and unresolved fields → local validation | Open-text name extraction and one coherent draft in one model call | Fluent, schema-valid misinterpretation; missed clauses or invented details |
| Jev first, Luna fallback | Jev proposal → route uncertain/inconsistent/extraction-gap cases to Luna using original input → validate | Straightforward cases may avoid Luna; fallback may recover candidate gaps | Hard cases wait through two sequential calls; confident Jev mistakes may never reach Luna |
| Luna + selective Jev check | Luna creates draft → selected semantic questions compare draft to original request → reconcile → validate | Potential detection of dropped negation, altered recurrence or swapped duration roles | Extra call can add delay and false alarms; agreement is not proof and disagreement does not identify the right model |

Do not add a model-based router just to choose these paths. Prototype routing with explicit conditions and corpus-derived policies. A new list alone does not require two models: Luna can already propose its name. Jev-first should fall back for extraction uncertainty; neither pipeline should invoke a second model merely to guess information absent from the sentence.

An always-parallel alternative starts Luna extraction and independent Jev questions together, then compares their shared fields. It can reduce sequential waiting but pays for both on every request. Because Jev does not yet have Luna's draft, this is independent extraction, not checking that draft. Compare this alternative only if selective checking proves useful but its sequential delay is unacceptable.

### Luna's proposed draft contract

Input: original description, relevant saved-list IDs/names, locale, time zone, supported behaviors and accepted defaults. Never send native picker tokens. Output: disposition (review / needs input / unsupported), existing/new list references, proposed new names with exact source excerpts when possible, one rule type, type-specific timing, access settings and an array of unresolved fields. This allows more than one missing detail without inventing a chat exchange.

Every proposed value carries provenance: explicit input, deterministic normalization, visible product default, or unresolved. Extracted excerpts must actually occur in the source, but their existence alone does not prove interpretation. An existing list reference must resolve to a supplied ID; duplicate names require selection. Missing names can be null rather than fabricated. New lists remain `contents_required` until the native selection is completed. Models propose neither app tokens nor save/activation commands.

Use typed controls and templates for follow-up questions: “Which Social list?”, “What time does the block start?”, “Which nights should start the block?” Do not depend on generated prose to identify what needs fixing. After user corrections, lock those fields against late model responses; changes to the original sentence invalidate stale interpretations. User app selection and manual timing edits do not require another remote parse.

### What Jev would check after Luna

Give Jev the original request, saved-list catalog, supported behavior contract and proposed draft, with each check scoped to one proposition:

| Check | Choices | Failure consequence |
| --- | --- | --- |
| List meaning preserved? | supported / contradicts explicit inclusion or exclusion / cannot determine | Resolve the affected list reference; never silently broaden targets |
| Recurrence preserved? | supported weekly / one-time intent lost / unclear / not applicable | Stop a one-time request from becoming weekly |
| Timing roles preserved? | supported / reversed or changed / unclear / not applicable | Ask about the specific disputed endpoint or duration |
| All explicit constraints represented? | yes / omitted requirement / unclear | Prevent a valid partial draft from swallowing a second window or exception |
| Ambiguity handled honestly? | resolved by source / genuine user input needed / unsupported guess | Ask only the missing decision, preserving other fields |

These are proposed checks, not proven validators. Local code still enforces IDs, numeric bounds, one-block scope, all-day intent, list contents and type consistency. Jev confidence is not a calibrated correctness score for Tyri. Do not compare it numerically with Luna self-reported confidence or vote by a combined score.

### Conflict, delay and failure behavior

1. **Missing user information:** both models seeing “after dinner” does not supply a clock time. Ask the user directly; preserve other fields.
2. **Recoverable parser uncertainty:** at most one alternate interpretation attempt in the proposed design, then targeted controls. Never run an open-ended model debate.
3. **Material disagreement:** use deterministic evidence when conclusive; otherwise ask a neutral field-specific question without exposing two competing AI answers as truth. Do not silently let Luna overwrite Jev or vice versa.
4. **Timeout/offline:** preserve the sentence and confirmed edits; offer Retry or manual list/day/time controls. A failed checker is not approval. If a check is required for that risk class, leave the affected fields unresolved; an optional observational check cannot change an already confirmed draft.
5. **Loading:** show one stable “Preparing your block…” state with Cancel and a manual alternative. Do not animate a ready-to-save schedule before validation finishes or overwrite it with a late fallback result.
6. **Genuine unsupported request:** explain the constraint promptly, before making the user select apps for a plan this path cannot represent. Neither model expands the accepted feature scope.

### Same user examples, different internal work

| Request | Desired experience | Jev-only | Luna-only | Combined |
| --- | --- | --- | --- | --- |
| Social media and Games weekdays 9:15am–5:40pm | Complete exact review, no extra questions | Membership and time components | One coherent draft | A second call must prove value on such easy cases |
| Block Shopping and News weekdays 9am–5pm | Both names prefilled when clear; choose apps for each; preserved timing | Depends on candidate recovery | Extract both names; require contents | Jev-first may need fallback; Luna-first needs no check merely for new names |
| Block my “After Hours” list weekdays 9pm–11pm | Recognize list name, not a vague time phrase | Candidate/name matching tested | Name/context extraction tested | Check only if a demonstrated confusion warrants it |
| Games weekdays except Friday 9am–5pm | Mon–Thu, same saved Games list | Negation-aware day choices | Coherent schedule with exception | Candidate for a semantic exclusion check |
| Games after dinner | Ask start time and other missing timing once | Missing/ambiguous outputs | Unresolved timing fields | No second model can discover dinner time |
| Games tomorrow 9am–11am | Unsupported one-time intent; no weekly substitute | Support classifier | Unsupported disposition | Recurrence check can detect a dropped date |
| Block 50 minutes after 40 minutes of use | Usage 40, lockout 50 | Separate role-specific choices | Typed duration fields | Check roles if evaluation shows this error class |

### Evaluation that optimizes the experience

Measure time until a **correct, reviewable** draft and time to completed schedule, not just model latency. Record p50/p95, percentage requiring questions, unnecessary questions, correction count, picker detour completion, cancellation recovery and success without retyping. Keep required app selection separate from avoidable clarification when counting user effort.

For the hybrid, report errors uniquely caught by Jev, errors introduced by its checks, disagreements resolved by the user, shared mistakes, fallback frequency and incremental latency/cost. Run all pipelines on the same cases; add single-provider outage and slow-response simulations. Begin any real comparison offline with labeled data; do not silently send live user text to a second provider for shadow checks. Provider data disclosure must match whichever pipeline is actually enabled.

Choose the simplest pipeline that meets the same severe-error gate and user-completion objective. Add Jev only if its incremental benefit survives held-out evaluation. Until measured, Luna alone is the proposed reference, not the selected winner; no speed, accuracy or “two models are safer” claim is established.

## Evidence and limitations

Read the handoff and current local sources: `Tyri/Views/ListOnboardingView.swift`, `Tyri/Views/AppGroupEditorView.swift`, `Tyri/Views/AppGroupListView.swift`, `Tyri/Views/DescribeBlockView.swift`, `Tyri/Models/BlockDescriptionDraft.swift`, `Tyri/Views/BlockEditorView.swift`, `Shared/BlockRule.swift`, and `Shared/BlockingSchedule.swift`. These are working-tree observations, not verification of shipped behavior. The Notion task contains historical discarded implementation notes; the current handoff and latest user directions govern this review.

Applied [grill-me](https://app.notion.com/p/826993f193644b7fa2f4a456678dfc0e) and its [grilling instructions](https://app.notion.com/p/4073ff0a4be94fe0a84a8d1a40aa3803). Publication is authorized by Amit's later message, not by the skill. No app simulator or physical enforcement test was performed for this design review. Any interactive artifact accompanying this report illustrates authored scenarios, not model inference or native picker behavior.
