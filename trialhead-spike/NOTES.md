# Spike Notes — M0 & M1

**Date:** 2026-08-14 · ClinicalTrials.gov API v2

- [M0 — API verification](#m0--api-verification-notes)
- [M1 — stage-1 parser results](#m1--stage-1-parser-results)

---

# M0 — API Verification Notes

Goal: confirm DESIGN.md §6 is accurate before building anything on it.

---

## Verdict

The API works as designed. No key, no auth, HTTP 200 throughout, and every
parameter §6 claimed exists does exist. **Three corrections to DESIGN.md** and
**four new complications** for the M1 parser.

---

## Confirmed working

| Thing | Result |
|---|---|
| `GET /api/v2/studies` | ✅ |
| `GET /api/v2/studies/{nctId}` | ✅ |
| `query.cond` | ✅ |
| `filter.overallStatus` | ✅ pipe-separated for multiple |
| `filter.geo=distance(lat,lon,50mi)` | ✅ **the important one** |
| `fields` with dotted paths | ✅ trims payload substantially |
| `countTotal=true` | ✅ |
| `pageToken` / `nextPageToken` | ✅ cursor pagination |
| No API key required | ✅ |

**Geo filter proof:** "breast cancer" + RECRUITING → 2,467 nationwide;
adding `distance(40.7128,-74.0060,50mi)` → 266. Works exactly as the product needs.

**Site geocoding:** `location.geoPoint.{lat,lon}` present. On NCT06545942,
18 of 18 sites geocoded. Distance sorting is viable.

---

## Corrections to DESIGN.md

### 1. Ages are strings, not integers

§8 modeled `minimumAge: Int?`. The API returns `"18 Years"` — value plus unit,
and the unit is not always years (`"6 Months"` appears for pediatric trials).
`maximumAge` is frequently absent entirely.

Handled by `AgeBound` in `Models.swift`, which parses value + unit and
normalizes to years. **DESIGN.md §8 updated.**

### 2. `phases` is optional, not guaranteed

Observational studies carry no `phases` field at all. NCT05134779 is
`OBSERVATIONAL` with no phase — a UI that force-unwraps phase will crash.

### 3. Study type needs filtering, and there's no dedicated parameter

Patients looking for treatment want **interventional** trials. Observational
studies pollute results. There is no `filter.studyType`; use the advanced
filter syntax instead:

```
filter.advanced=AREA[StudyType]INTERVENTIONAL
```

Verified: 266 → 234 for the NYC breast cancer query, and every remaining
result has a phase. **Add to §6.**

---

## New complications for M1

### 4. Nesting goes three levels deep

Real example (NCT06545942):

```
1. Age ≥ 18 years
2. Have histologically confirmed disease for each treatment arm as follows:

   1. Treatment Arm 1 (MOMA-313 Monotherapy)

      \- Advanced ... solid tumors ... with any HR-deficient alteration.
   2. Treatment Arm 2 (MOMA-313 in Combination with Olaparib):

      * Dose escalation: ...
      * Dose optimization: ...
3. Have at least 1 lesion at baseline ...
```

Flat splitting would turn criterion 2 into five unrelated fragments. Stage 1
must preserve hierarchy — parent criterion with children, rendered as an
expandable row.

### 5. The text contains escaped markdown

`\-`, `\*\*`, `\[`, `\]` appear literally in the strings. Must unescape before
display or users see backslashes. Cheap fix, easy to forget.

### 6. Comparators are Unicode

`ECOG PS ≤ 2`, `Age ≥ 18 years`. Not `<=` / `>=`. Any regex for numeric
thresholds needs `≥ ≤ < > =` and their ASCII equivalents.

### 7. Header variants are broader than assumed

Across 50 sampled studies:

| Header | Count |
|---|---|
| `Inclusion Criteria:` | 40 |
| `Exclusion Criteria:` | 38 |
| `Key Inclusion Criteria:` | 4 |
| `Key Exclusion Criteria:` | 4 |
| `Inclusion Criteria` (no colon) | 2 |
| `Main Study Inclusion Criteria:` | 1 |
| Cohort-specific (`Inclusion Criteria for Cohort 3:`) | several |
| Numbered (`1.2. Inclusion criteria: Substudy 4 ...`) | 2 |

**47 of 50 (94%) match a case-insensitive `inclusion criteria` /
`exclusion criteria` probe.** Stage 1 is viable; it just needs a permissive
regex rather than an exact-string match.

### 8. Multi-cohort trials have criteria that vary by arm — open question

Some studies define separate inclusion blocks per cohort or substudy. A single
flat checklist misrepresents these. v1 options:

- **(a)** Detect multiple cohort blocks, show a banner: "criteria vary by
  treatment group — review with your care team," render all of them
- **(b)** Let the user pick a cohort
- **(c)** Show only shared criteria

Leaning (a) — honest, cheap, and doesn't ask a layperson to self-assign to an arm.
**Needs a decision in M1.**

---

## Also confirmed

**Per-site status differs from trial status.** NCT06545942 is `RECRUITING`
overall while its San Francisco site is `COMPLETED`. DESIGN.md §5.5 already
called this — good, and it's now proven rather than assumed.

**Corpus size for M1:** 2,457-char median, 12,009 max across the saved sample.
Long enough that criteria count per trial will typically be 15–40 rows.

---

## Artifacts

```
trialhead-spike/
├── Package.swift
├── Sources/TrialheadSpike/
│   ├── Models.swift    Codable mirror + AgeBound parser
│   ├── API.swift       client: search, study(nctId), raw
│   └── Spike.swift     CLI: fetch / search / dump
└── samples/            50 criteria blobs, 3 conditions — M1 input
```

```
spike fetch <NCT_ID>            fetch one study, print eligibility blob
spike search <condition>        recruiting interventional trials near NYC
spike dump <condition> <count>  save N blobs to samples/
```

Sample corpus: 20 breast cancer, 15 type 2 diabetes, 15 Alzheimer's.
50 files, 292–12,009 chars, median 1,711.

---

---

# M1 — Stage-1 Parser Results

**Verdict: the checklist design holds.** Target was ≥80% clean. Result:

| Corpus | Studies | Clean | Mangled | Unparseable |
|---|---|---|---|---|
| **Holdout** (unseen conditions) | 45 | **96%** | 2% | 2% |
| Train (tuned against) | 50 | 100% | 0% | 0% |
| **Combined** | **95** | **98%** | 1% | 1% |

**The holdout number (96%) is the real one.** The train corpus hit 100% only
because the parser was iterated against it — that's overfitting, and quoting it
as the headline would be dishonest. Holdout conditions: rheumatoid arthritis,
sickle cell disease, Parkinson's, ulcerative colitis. None seen during tuning.

Corpus totals: 1,743 criteria extracted across 95 studies. Median 15 criteria
per study, max 52 — so the §5.4 checklist screen needs to handle ~15–50 rows
comfortably, with section grouping and filtering. That validates the filter
chips in the wireframe.

## What the parser does

`Parser.swift`, ~200 lines, zero dependencies, no model, no network.

1. **Normalize inline bullets** — some sponsors put every criterion on one line
   using `\*` as separators (see failure mode 3 below)
2. **Unescape markdown** — `\-`, `\*\*`, `\[`, `\]` appear literally
3. **Detect section headers** — permissive regex, anchored on a trailing colon
   or end-of-line so prose doesn't false-positive
4. **Split into criteria** — bullets (`*`, `-`, `•`, `1.`, `a)`, `iv.`), with
   unbulleted lines merged as continuations
5. **Rank indentation into depth levels** — indent width varies (2, 3, 4 spaces
   all appear), so levels are ranked per study rather than assumed

## Header variants that had to be handled

Each of these was a real failure found by inspecting a flagged study:

| Variant | Example | Source |
|---|---|---|
| Role-scoped (dyad studies) | `Daughter of Cancer Survivor Inclusion Criteria:` | NCT05721976 |
| Parenthetical scope | `Inclusion Criteria (All Participants):` | NCT07221344 |
| Bulleted header | `* INCLUSION CRITERIA:` | NCT06313398 |
| Cohort-scoped | `Inclusion Criteria for Cohort 3:` | several |
| Numbered prefix | `1.2. Inclusion criteria: Substudy 4 …` | 2 studies |
| `Key` / `Main Study` prefix | `Key Inclusion Criteria:` | 9 studies |

## Two false positives in my own scoring

Worth recording, because both would have led to wasted work:

1. **Length ≠ unsplit.** The first heuristic flagged any criterion >600 chars as
   a parse failure. Inspection showed these are usually *legitimate* — a single
   criterion carrying an inline definition ("Postmenopausal status is defined
   as…"). Long rows are a **UI problem** (truncate-and-expand), not a parser
   problem. Replaced with a chars-per-criterion ratio check.

2. **Mentioning "inclusion criteria" ≠ a buried header.** The swallow-detector
   matched any occurrence of the phrase, so it flagged
   *"…whose primary lesions all meet the inclusion criteria, or…"* — a criterion
   legitimately referencing the criteria in prose. Now requires header
   punctuation (optional parenthetical, then a colon).

Both inflated the apparent failure rate. Always read the flagged study.

## Residual failure modes

**1. Unstructured prose (~2%, not fixable with rules).** NCT05685368 runs every
criterion together in one paragraph with no bullets or line breaks:

> "The inclusion criteria for study participation are Be an adolescent and/or
> young adult (age 14-21) who has Sickle Cell Disease Willing to enroll in the
> ACT group…"

No deterministic split exists. **Product decision required** — see below.

**2. Sub-headers and connectors as criteria (cosmetic).** Rows like
`HU Regimen:` or a bare `or` appear when a list has internal structure.
Filterable: short rows ending in `:` are sub-headers, not criteria. Low priority.

**3. Inline `\*` separators (fixed).** NCT07716176 put all 22 criteria on two
lines. Detected by counting escaped asterisks per line (≥3, with `\*\*` bold
masked out first) and restoring the breaks. Went from 1 unsplit blob to 9
inclusion + 13 exclusion criteria.

## Decisions this forces

**A. Graceful degradation when parsing fails (~2–4% of studies).** The checklist
cannot be built for these. The app must detect a failed parse and fall back to
showing the **verbatim criteria text** with a note — "we couldn't break this
study's criteria into a checklist; here is the original text." Never show an
empty or half-built checklist. This is a required v1 behavior, not a nicety.

**B. Cohort-scoped criteria are rarer than feared.** 3 of 50 train and 1 of 45
holdout studies carried cohort headers — roughly 4%. Option (a) from DESIGN.md
§11.7 (render all blocks with a "criteria vary by treatment group" banner) is
cheap and sufficient. **Recommend closing §11.7 in favor of (a).**

**C. Max nesting depth observed is 2**, not 3 as M0 estimated. Parent + one
level of children covers everything in 95 studies. The UI needs one level of
expandable sub-rows, not an arbitrary tree.

## Commands

```
spike split <NCT_ID>   stage-1 split one sample, print the tree
spike score            run stage-1 over samples/, grade the corpus
```

Corpora: `samples/` (50, train) and `samples-holdout/` (45, unseen).
Swap directories to score the other set.

---

# M2 — Categorisation and Verdicts

**Built:** `Profile.swift`, `Categorizer.swift`, `Evaluator.swift`.
**Commands:** `spike evaluate <NCT_ID> [diabetes]`, `spike measure`.

## The headline finding

Measured across 609 rules from 25 breast-cancer trials, using a matched profile:

| Verdict | Share |
|---|---|
| 🟢 green (satisfied) | **13.5%** |
| 🟠 amber (ask) | **86.5%** |
| 🔴 red (blocked) | **0%** from text |

Re-measured on a 50-study mixed corpus: 13.0% / 87.0% / 0%. The number is
stable, so it isn't an artefact of one condition or one profile.

**Red verdicts work, but only from the structured age/sex fields.** Verified
against a prostate-cancer trial with a female profile — correctly flagged
"enrols male participants only." Those two fields are exact values from the
trial record, not guesses from prose, so a "no" there is trustworthy.

## What kind of rule is each one?

| Category | Share |
|---|---|
| **other** (unidentified) | 45.6% |
| prior treatment | 16.9% |
| diagnosis | 12.3% |
| lab value | 7.9% |
| pregnancy | 5.1% |
| age | 4.4% |
| consent | 3.4% |
| performance status | 2.6% |
| sex | 1.3% |
| BMI | 0.3% |

## What this means for the design

**The `🟢 9 / 🟠 3 / 🔴 0` badge on search-result cards (§5.2) doesn't work.**
Every trial scores roughly 13/87/0, so the badge can't help anyone compare one
trial against another. It looks informative and isn't.

This is not a failure of the parser — it's the honest shape of the problem.
Most eligibility rules genuinely *cannot* be answered without bloodwork,
imaging, or a clinician. The design was optimistic about how many would resolve.

**Recommended changes:**

1. **Drop the three-colour count from result cards.** Replace with what actually
   discriminates between trials: distance to nearest site, phase, and a plain
   count of questions to ask.
2. **Use age/sex blockers as a filter, not a badge.** They're reliable and
   genuinely narrow the list. Hide or flag categorically ineligible trials
   rather than showing a red "0" on every card.
3. **Reframe the checklist from scoring to preparation.** Lead with
   "17 questions for the study team," not "how well you fit." That was always
   the real value — the measurement just proved it quantitatively.
4. **Keep the colours inside the trial detail screen.** Per-rule they're still
   useful: green rows are ones the person can stop worrying about.

## A measurement mistake worth recording

The first `measure` run scored a breast-cancer profile against a corpus that was
60% diabetes and Alzheimer's trials. Naturally the person's own words rarely
appeared. Re-running with a condition-matched corpus changed the result by
0.5 percentage points — the flaw didn't matter here, but only checking revealed
that. Match the profile to the corpus before quoting any number.

## Categoriser bug found and fixed

"Type 2 diabetes mellitus" was landing in `other` and going amber, for a person
whose profile literally said "type 2 diabetes." The categoriser only looked for
generic keywords ("diagnosed", "biopsy") and never checked the strongest signal
available: **whether the person's own words appear in the rule.**

Fixed by checking profile terms first, with a tie-break — if the rule also
carries history language ("prior", "previously", "received"), it's a treatment
rule; otherwise it's a diagnosis rule.

Note what stayed amber after the fix, correctly: *"Type 1 diabetes or other
non-type 2 forms of diabetes"* for a type-2 patient. The phrase "type 2
diabetes" doesn't literally appear, so no match, so amber. Safe outcome.

## Still open

- **45.6% of rules land in `other`.** Better keywords would label more of them,
  but most are comorbidities and disease specifics that stay amber regardless.
  Worth improving for display quality, not for verdicts.
- **Sub-headers still leak through as rules** (`HU Regimen:`, a bare `or`) —
  filter short rows ending in a colon.
- **Consent rules are marked green** ("standard for all trials"). Defensible,
  but it inflates the green count slightly. Consider excluding them from counts
  entirely rather than colouring them.

---

# M3 — First Working App

Built in `/Users/ruhitabassum/code/Trialhead/`. Runs on the iPhone simulator
against live ClinicalTrials.gov data.

**Screens:** results list (`MatchesView`), trial detail with checklist
(`TrialDetailView`), profile settings (`ProfileView`), tab bar (`ContentView`).
**Plumbing:** `TrialsStore` (fetching + state), `TrialAnalyzer` (study + profile
→ card data).

## The logic layer moved across unchanged

All six research files — `Models`, `API`, `Parser`, `Profile`, `Categorizer`,
`Evaluator` — compiled into the iOS app with **zero edits**. That's the payoff
from the §9 rule about keeping them free of UI framework imports. Any future
Android port inherits the same property.

## Finding: site coordinates are city-level, not street-level

Every trial initially showed **"0.1 mi"**. Investigating: Memorial Sloan
Kettering is listed at `40.71427, -74.00597` — which is the New York City
centroid, not the hospital's actual Upper East Side address. ClinicalTrials.gov
geocodes sites **to the city**, so every "New York" site shares one coordinate.

**This partially undermines the M2 card redesign.** Distance was named "the
strongest real differentiator" — but within a metro area it cannot differentiate
at all, because every local trial returns the same distance. It only
discriminates at the between-cities scale (Buffalo vs. New York).

**Fix applied:** lead with the city name; show mileage only past 20 miles, where
it reflects a real travel decision.

- Before: `0.1 mi · nearest of 85 sites` — invented precision implying a walk
- After: `New York · nearest of 85 sites`

**Still open:** the cards now need a different primary differentiator. Phase and
question count are weak. Worth considering: sponsor type (academic vs industry),
enrollment size, or how recently the record was updated — a trial not touched in
two years is often stale regardless of its "recruiting" label.

## Finding: sub-headings were inflating every question count

The checklist rendered `Treatment Arm 1 (MOMA-313 Monotherapy)` as a question
with an amber dot. It isn't a question — it's a label for the rows beneath it.
Same for `Have histologically confirmed disease for each treatment arm as
follows:` and stray `or` rows.

Added `Criterion.isHeading`, true when a row has nested children *and* looks
like a label (ends in a colon, or is under 60 characters), or is a bare
connector. Headings render as quiet grey text with no dot and are excluded from
counts.

Effect on one study: **26 → 22 questions.** The heuristic errs toward marking
things as headings, because undercounting questions is safer than overcounting —
the row still displays either way.

## Note: the project was bootstrapped without Xcode's UI

`project.pbxproj` was written by hand using Xcode 16+ file-system-synchronized
groups, which reference a folder rather than listing every file. Verified by
building and running. Practical upshot: new `.swift` files dropped into
`Trialhead/Trialhead/` are picked up automatically, no project edits needed.

## Duplication to be aware of

The six logic files now exist in two places: `trialhead-spike/Sources/` (for
corpus scoring) and `Trialhead/Trialhead/Core/` (the app). They're currently
identical and were synced by hand. If they drift, the spike's scores stop
describing the app's behaviour. Options later: point the spike's `Package.swift`
at the app's `Core/` folder, or retire the spike once its scoring job is done.

---

# M4 — Usable For Real (in progress)

Three of five items done. `LocalStore.swift`, `ContactSheet.swift`, `SavedView.swift`.

## Persistence

One JSON file in the app's Application Support folder, written on every change
via `didSet`. Holds profile, search settings, and saved trial IDs.

A single file makes the privacy claim checkable rather than asserted — "delete
everything" removes exactly one thing, and the Profile screen says so.

Verified by writing a state file directly into the simulator's app container and
confirming every field loaded, including a BMI computed from the stored height
and weight.

## Contact sheet

The app's stated purpose, and until now the least finished part of it.

- Site contacts listed before the central one — they're closer to actual screening
- **Deduplicated on phone+email.** The same coordinator is routinely listed both
  against a site and centrally; without this, one person appeared twice under two
  different headings
- Editable draft message assembled from the profile plus the top amber criteria,
  capped at four questions — a coordinator facing forty bullet points answers none
- Reached from a button placed **above** the checklist. Burying it under forty
  rows of criteria would mean most people never reach it

## Saved trials

Saved trials are re-fetched **by NCT ID**, not filtered out of the current search
results. Filtering was the obvious implementation and it's wrong: something saved
while searching "breast cancer" would silently vanish the moment you searched for
something else.

Incidental confirmation from testing: a saved Gothenburg study displayed
"3,780 mi", which is correct, and shows the distance logic works fine at the
scale where distance actually means something. It's only *within* a metro area
that city-level geocoding makes it useless.

## Search area: ZIP, city, and a capped radius

`LocationSheet.swift` + `LocationResolver.swift`. Three filters — ZIP code, city,
and a travel-radius slider running 5–30 miles.

Apple's `CLGeocoder` turns the typed ZIP or city into coordinates on-device. No
API key, no third-party service, and the query carries no health information.

**The 30-mile cap is deliberate.** Trials commonly need weekly in-person visits,
and travel is among the most common reasons people stop taking part. A 250-mile
radius produces a longer list that is mostly false hope.

## The bug that would have lost real users' data

**Symptom:** a seeded test profile silently vanished between runs.

**Cause:** Swift's automatic `Codable` decoding requires *every* property to be
present in the JSON. Adding three fields to `SearchSettings` meant every
previously saved file failed to decode — and `LocalStore.load()` fell back to a
blank state, discarding the profile, the settings, and the saved trials.

In a shipped app: **user installs an update, opens it, everything is gone.**

**Verified rather than assumed.** Wrote an old-format file with
`"condition": "melanoma"` and no location fields, launched, and watched the app
display "breast cancer" — the default. After the fix, the same file loads as
melanoma with the missing fields defaulted.

**Fix:** hand-written `init(from:)` for `Profile`, `SearchSettings`, and
`StoredState` using `decodeIfPresent` with fallbacks. Placed in extensions so the
memberwise initialisers survive.

**Rule going forward:** every field added to saved data must decode leniently.
This is only testable by keeping an old-format file around — worth adding a real
test for once there's a test target.

## Two SwiftUI lifecycle traps

**`onChange` fires after `onAppear`.** Restoring the saved ZIP/city mode in
`onAppear` counted as a change, so the `.onChange(of: mode)` handler that clears
the text field ran afterwards and wiped the value just restored. A boolean guard
set at the end of `onAppear` doesn't help — it's already true by then. Moving the
clearing into a custom `Binding` fixed it, because a binding's setter only runs
when something actually sets it.

**Toolbar `Label`s hide their text.** `.labelStyle(.titleAndIcon)` didn't
override it either. The search location ended up shown as a bare icon — the same
discoverability failure as the iOS 26 back button. Replaced with a labelled,
tappable row at the top of the results list.

## Still open in M4

- **Nearest-site status bug** — `nearestSite` ignores per-site status, so a
  COMPLETED site can be presented as the nearest one. Sampled trials had 3 of 85
  and 4 of 18 sites closed while the trial recruited. Sends someone to a dead
  end; fix before building the map.
- Sites map (§5.5). Data check tempered its value: per-site contacts are rare
  (5 of 85, 0 of 18), so the central contact does most of the work.
- A stronger primary differentiator for result cards, unresolved since M3.

## Next: M5

Onboarding flow (§5.1), then real-world hardening — offline states, VoiceOver,
Dynamic Type — then watching five real people use it.
