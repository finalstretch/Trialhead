# Trialhead — Design Document

> Working name. A trailhead is where a journey starts, which is roughly the app's job.

**Status:** draft v0.9 · **Last updated:** 2026-08-16 · **M0–M4 complete, onboarding built**
**Framing:** a preparation tool, not an eligibility calculator (§1)
**Architecture:** fully on-device, no backend, no model in v1 (§7)
**Parser:** 96% clean split on unseen studies (M1) — the design holds
**Verdicts:** 13.5% green / 86.5% amber (M2) — result cards redesigned (§5.2)
**Platform:** iOS (SwiftUI) · **Data:** ClinicalTrials.gov API v2

---

## 1. Thesis

Finding a clinical trial is not a search problem. It's a **preparation** problem.

ClinicalTrials.gov already returns every recruiting trial for a condition. What it doesn't do is help anyone act on them. Eligibility criteria arrive as an unstructured wall of clinical text, site locations are buried in a list, and the phone number of the person who could actually answer your questions is three taps down a page nobody scrolls.

Trialhead turns that wall into a checklist of **questions worth asking**, puts travel distance on the front of every result, and makes contacting the study coordinator a single tap.

**One-line pitch:** Trialhead helps patients and caregivers find nearby clinical trials and walk into the conversation already knowing what to ask.

> **This framing is a measured conclusion, not a preference.** M2 established that only ~13% of eligibility rules can be resolved from what a person can reasonably be asked to type; the rest need bloodwork, imaging, or clinical judgement. An app promising to tell you whether you qualify would be lying. An app that gets you to the study coordinator with the right questions is both honest and genuinely more useful — that call is the step most people never take.

---

## 2. User

**Primary:** the caregiver — an adult child or spouse researching on behalf of someone recently diagnosed or out of standard options. Motivated, overwhelmed, not clinically trained, often researching at 2am.

**Secondary:** the patient doing the same for themselves.

**Explicitly not v1:** clinicians, research coordinators, trial sponsors. Different product.

### Why they're underserved

- Most trial referrals come from specialists at academic medical centers; the large majority of US patients are treated in community practices that run far fewer trials.
- The existing website is a research database with a public front-end, not a patient tool.
- Travel burden — the most common practical reason people never enroll — is invisible until deep into the process.

---

## 3. Principles

1. **Never assert eligibility.** The app says "here's what to ask about," never "you qualify." Eligibility is determined by the study team after screening. This is an ethical requirement and a legal one.

   **Corollary (M2):** the app is measured by whether someone makes a better phone call, not by how many rules it resolves. A screen full of amber rows is a *success* — it's a prepared patient. Resist any design that implies a fit score.
2. **Verbatim source is always one tap away.** Any parsed or simplified text must link to the original. The parser is a navigation aid over authoritative text, never a replacement.
3. **Health data never leaves the device.** No accounts, no sync, no analytics on health fields in v1. Data not collected can't leak.
4. **Uncertainty resolves to "ask," never to "blocker" or "match."** A wrong red mark could stop someone from pursuing a trial that would have helped them. Bias every ambiguous parse toward the conversation list.
5. **Distance is a first-class attribute**, shown everywhere a trial is shown.

---

## 4. Scope

### v1 (ship this)
- On-device profile
- Match list driven by profile
- Trial detail with plain-language summary
- Eligibility checklist (the centerpiece)
- Site map + nearest-site distance
- One-tap contact of the study coordinator
- Local saved list

### v2 / Phase 2 (after v1 works)
- **On-device model for plain-language restatement** of criteria rows — progressive enhancement over the rules parser, never a correctness dependency (§7)
- Background refresh + change notifications ("a site opened 12 miles from you")
- PDF "doctor packet" export
- Multiple profiles for caregivers managing more than one person
- Results data for completed trials
- Android, if the logic layer proves worth sharing (§9)

### Explicitly out of scope
- Anything that reads like clinical decision support
- Symptom tracking, medication management, EHR integration
- Accounts, cloud sync, social features

---

## 5. App Layout

### Navigation

```
TabView
├── Matches      (NavigationStack) ← default tab
│   └── Trial Detail
│       ├── Eligibility Checklist
│       ├── Sites Map
│       └── Contact Sheet
├── Saved        (NavigationStack)
│   └── Trial Detail (same destination)
└── Profile      (NavigationStack)
    ├── Edit Condition
    ├── Edit Treatment History
    ├── Edit Location
    └── About / Disclaimers / Sources
```

First launch pushes a full-screen onboarding flow before the tabs appear.

---

### 5.1 Onboarding — Profile Builder

Multi-step, one question per screen, progress dots. Every step skippable except condition. Ends on a privacy statement, which is a feature and should look like one.

```
┌───────────────────────────────────────┐
│  ● ● ○ ○ ○                    Skip    │
│                                       │
│  What are you looking                 │
│  for trials for?                      │
│                                       │
│  ┌─────────────────────────────────┐  │
│  │ 🔍 breast cancer                │  │
│  └─────────────────────────────────┘  │
│                                       │
│   Breast Cancer                       │
│   Male Breast Cancer                  │
│   Triple Negative Breast Cancer       │
│   Inflammatory Breast Cancer          │
│                                       │
│  ┌─────────────────────────────────┐  │
│  │           Continue              │  │
│  └─────────────────────────────────┘  │
└───────────────────────────────────────┘
```

**First-run order (revised 2026-08-16):** welcome → **guided walkthrough (§5.1b)** → condition → age & sex → height & weight → location + travel radius → done.

> **The walkthrough sits between the two halves of onboarding, not after them.** Someone who has seen the app work understands why it's asking for their height, and is far likelier to answer. Asking first and explaining later gets the order of persuasion backwards.
>
> Consequences worth knowing: the tour runs against the app's **default search** (an example location and condition), so its copy says so plainly rather than implying the results are the person's own. Whatever condition they pick during the tour is **carried into the setup field**, so nobody is asked the same question twice. And the first setup question has no Back button — behind it is the entire walkthrough, which belongs to an earlier phase.

> **Treatments and medications are deliberately NOT asked during setup.** They sharpen the question lists more than anything else, but they're also the highest-friction fields in the app — asking someone to recall their treatment history *before* they've seen what a trial page even looks like is how you lose them at setup. They live in Profile, and the closing screen points there once the person has had a look around.

**Required:** condition and location — without them there's nothing to search and nowhere to search from. **Skippable:** age & sex, height & weight.

**Units:** height and weight are asked in feet, inches and pounds, and stored as centimetres and kilograms. The app is US-only (§11.4) and nobody there knows their height in centimetres; trial criteria are written in metric.

Condition should eventually autocomplete against a controlled vocabulary rather than accepting raw free text — see Open Questions.

---

### 5.1b Guided walkthrough

Runs once, **between the welcome screen and profile setup** — see the order note in §5.1. `Tour.swift` + `TourOverlay.swift`.

Each step blurs the screen except one component, ringed and sharp, with a card explaining what it does and a **Got it** button. Twelve steps in three acts:

**On the trials list** — search bar → search area → stage of testing.

**Two interactive steps.** The person picks a condition from five suggestions, then taps a trial themselves. Reading about a feature and using it are different things; a tour nobody touches teaches very little. These steps show "Your turn" instead of a button and wait for the action.

**On the trial page** — requirements → where it happens → questions to ask → contact the study team. The detail screen scrolls each target into view before the spotlight points at it.

**Then out** — the Profile tab (where treatments live, deliberately not asked during setup) and the Saved tab, before returning to the list.

Skippable at every non-interactive step. Completion is stored, so it runs once; "Delete everything" resets it along with the profile.

**Touches pass through where a step expects them.** The backdrop blocks taps by default, so nobody wanders off mid-explanation. Two exceptions: the interactive steps, and the **requirements** step — that list runs to dozens of rows, and describing it while forbidding anyone to scroll it teaches very little.

**Spotlights are clamped to the screen.** The requirements checklist is often taller than the display, and an un-clamped cut-out would leave no visible backdrop at all. A target scrolled entirely off-screen falls back to dimming everything rather than pointing somewhere wrong.

**The tab-bar spotlight covers the whole bar**, extended into the bottom safe area, so Saved and Profile are both fully sharp while the callout names the one it's describing. Individual `tabItem` frames can't be measured, and a half-blurred tab bar reads as a rendering fault rather than a highlight.

**Implementation note.** Targets publish their frames with `anchorPreference`; the overlay resolves them through a `GeometryProxy` and punches a hole in a `.ultraThinMaterial` backdrop using a `destinationOut` mask. `ignoresSafeArea` must sit on the *GeometryReader*, not inside the overlay — applied inside it expands the drawing area after measurement and every spotlight lands a status-bar height too high.

This is also why the trials list uses a hand-rolled search field rather than `.searchable`: the system control's frame can't be measured, so the tour couldn't point at it.

---

### 5.2 Matches

Ranked list of trials. Ranking blends relevance, distance, and how few blockers the profile hits. Filter bar is a horizontal scroll of chips.

```
┌───────────────────────────────────────┐
│  Matches                        ⚙︎    │
│  ┌─────────────────────────────────┐  │
│  │ 47 trials · within 50 mi        │  │
│  └─────────────────────────────────┘  │
│  ▸ Stage of testing                   │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ ● RECRUITING      PHASE 2         │ │
│ │                                   │ │
│ │ Pembrolizumab Plus Chemotherapy   │ │
│ │ in Advanced Triple-Negative...    │ │
│ │                                   │ │
│ │ Memorial Sloan Kettering          │ │
│ │ 📍 14 mi · nearest of 6 sites     │ │
│ │                                   │ │
│ │ 12 questions to ask               │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ ● RECRUITING      PHASE 1/2       │ │
│ │ A Study of ARX788 in HER2...      │ │
│ │ 📍 31 mi · nearest of 2 sites     │ │
│ │ 18 questions to ask               │ │
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘
```

> ⚠️ **Revised after M2 measurement.** The `✓ / ⚠ / ✕` triple above **does not work on result cards**. Measured across 609 real rules, every trial scores roughly 13% green / 87% amber / 0% red — so the badge looks informative but can't distinguish one trial from another. Most eligibility rules genuinely can't be answered without bloodwork or a clinician; the original design was optimistic about how many would resolve.
>
> **Replacement card design:**
> - **Nearest site location** — see the M3 caveat below
> - **Phase and status**
> - **"17 questions to ask"** — a preparation signal, not a fit score
> - **Age/sex ineligibility as a filter**, not a badge. Those two come from exact fields in the trial record and are trustworthy, so use them to hide or flag categorically ineligible trials rather than printing a red `0` on every card.
>
> The three colours stay **inside the trial detail screen** (§5.4), where they're still useful per-rule: a green row is one the person can stop worrying about.

> ⚠️ **M3 caveat on distance.** ClinicalTrials.gov geocodes sites **to the city centre, not the street address** — every "New York" site shares one coordinate, so within a metro area distance can't differentiate between trials at all. It only discriminates between cities. Cards therefore lead with the **city name**, showing mileage only past 20 miles where it reflects a genuine travel decision. Never show sub-mile precision; it's invented.
>
> **Still open:** cards need a stronger primary differentiator. Candidates — sponsor type (academic vs industry), enrollment size, or record staleness, since a trial untouched for two years is often inactive regardless of its "recruiting" label.

Note the wording throughout — *likely*, *to ask* — never *eligible*.

**Phase filter (built 2026-08-16).** A collapsible "Stage of testing" section sits under the location row, with a checkbox per phase — Early Phase 1, Phase 1–4, and **No phase** — each carrying a one-line plain-English explanation and a live count of matching trials. Empty selection means *show everything*, never *hide everything*.

The explanations are the point, not decoration. "Phase 1" is research vocabulary; "the first testing in people, mainly about safety and finding the right dose" is something a caregiver can act on. The section footer adds the caveat that a higher number isn't automatically better — it depends on the person's situation.

**"No phase" needs saying out loud.** The API returns no phase for device, surgical, behavioural and dietary studies. That isn't missing data, and users will assume it is unless told. Combined studies list several phases and are counted under each, so per-phase counts can exceed the number of trials.

**States to design:** loading (skeleton cards), empty (no trials — offer to widen radius or drop filters), offline (show cached with a banner), error.

---

### 5.3 Trial Detail

Scrolling stack. Order matters: answer "is this for me" before "what is this."

```
┌───────────────────────────────────────┐
│  ‹ Back                      ♡   ⋯    │
│                                       │
│  ● RECRUITING · PHASE 2               │
│  NCT05123456                          │
│                                       │
│  Pembrolizumab Plus Chemotherapy      │
│  in Advanced Triple-Negative          │
│  Breast Cancer                        │
│                                       │
│  Memorial Sloan Kettering Cancer      │
│  Center · 6 sites                     │
│                                       │
│  ┌─────────────────────────────────┐  │
│  │  12 questions to ask         ›  │  │
│  │  3 things already look fine     │  │
│  └─────────────────────────────────┘  │
│                                       │
│  ┌─────────────────────────────────┐  │
│  │  📞 Contact study team          │  │
│  └─────────────────────────────────┘  │
│                                       │
│  WHAT THIS STUDY IS                   │
│  This study tests whether adding      │
│  pembrolizumab to standard chemo...   │
│                        Read full ›    │
│                                       │
│  NEAREST SITE                         │
│  ┌─────────────────────────────────┐  │
│  │        [ Map, 6 pins ]          │  │
│  └─────────────────────────────────┘  │
│  MSKCC, New York NY · 14 mi           │
│  See all 6 sites ›                    │
│                                       │
│  WHAT'S INVOLVED                      │
│  2 arms · randomized · ~430 people    │
│  Est. completion Mar 2028             │
│                                       │
│  ─────────────────────────────────    │
│  Source: ClinicalTrials.gov           │
│  Retrieved Aug 11, 2026               │
│  View full record ↗                   │
│                                       │
│  ⓘ This app does not determine        │
│    eligibility. Only the study team   │
│    can do that.                       │
└───────────────────────────────────────┘
```

---

### 5.4 Eligibility Checklist — the centerpiece

This screen is the product. Everything else is scaffolding around it.

```
┌───────────────────────────────────────┐
│  ‹ Eligibility                        │
│                                       │
│  [ Questions 12 ] [ Looks fine 3 ]    │
│                                       │
│  ⓘ Most rules need bloodwork or your  │
│    doctor's judgement. That's normal. │
│    This is your question list, not a  │
│    verdict.                           │
│                                       │
│  INCLUSION                            │
│  ┌───────────────────────────────────┐│
│  │ ✓  Age 18 years or older          ││
│  │    You entered 62                 ││
│  ├───────────────────────────────────┤│
│  │ ✓  Female                         ││
│  ├───────────────────────────────────┤│
│  │ ⚠  ECOG performance status of     ││
│  │    0 or 1                         ││
│  │    Ask your care team        ⌄    ││
│  ├───────────────────────────────────┤│
│  │ ⚠  Adequate organ function per    ││
│  │    protocol lab values            ││
│  │    Needs recent bloodwork    ⌄    ││
│  └───────────────────────────────────┘│
│                                       │
│  EXCLUSION                            │
│  ┌───────────────────────────────────┐│
│  │ ✓  No active CNS metastases       ││
│  ├───────────────────────────────────┤│
│  │ ⚠  No prior PD-1/PD-L1 inhibitor  ││
│  │    You listed pembrolizumab  ⌄    ││
│  │    ┌─────────────────────────────┐││
│  │    │ ORIGINAL TEXT               │││
│  │    │ "Prior therapy with an      │││
│  │    │ anti-PD-1, anti-PD-L1, or   │││
│  │    │ anti-CTLA-4 agent"          │││
│  │    └─────────────────────────────┘││
│  └───────────────────────────────────┘│
│                                       │
│  ┌─────────────────────────────────┐  │
│  │  Copy questions to ask      ⧉   │  │
│  └─────────────────────────────────┘  │
└───────────────────────────────────────┘
```

**Row anatomy:** verdict glyph · plain-language restatement · why-this-verdict line · disclosure chevron revealing verbatim source text.

**Verdicts:** `match` (green ✓) · `ask` (amber ⚠) · `blocker` (red ✕) · `unknown` → rendered as `ask`.

Note the example above: a prior-therapy hit renders **amber, not red**, because the profile's free-text medication entry isn't reliable enough to rule someone out. Principle 4 in action.

Accessibility: never encode verdict in color alone — glyph plus VoiceOver label ("to ask: ECOG performance status").

---

### 5.5 Sites Map

```
┌───────────────────────────────────────┐
│  ‹ Sites (6)              [Map|List]  │
│  ┌───────────────────────────────────┐│
│  │                                   ││
│  │      ◉ 3        ◉                 ││
│  │   ★ you                           ││
│  │            ◉ 2                    ││
│  └───────────────────────────────────┘│
│                                       │
│  ● Memorial Sloan Kettering           │
│    New York, NY · 14 mi · Recruiting  │
│    ┌──────────┐ ┌──────────────────┐  │
│    │ Directions│ │ Contact site     │  │
│    └──────────┘ └──────────────────┘  │
│                                       │
│  ● NYU Langone Health                 │
│    New York, NY · 19 mi · Recruiting  │
└───────────────────────────────────────┘
```

Sites carry their own recruiting status — a trial can be recruiting overall while a specific site isn't. Show per-site status; don't collapse to the trial level.

---

### 5.6 Contact Sheet

The friction this removes is the entire point: most people don't know that calling a study coordinator is normal, expected, and welcome.

```
┌───────────────────────────────────────┐
│  Contact study team              ✕    │
│                                       │
│  Research coordinators are there to   │
│  answer exactly these questions.      │
│  Calling is normal and free.          │
│                                       │
│  ┌─────────────────────────────────┐  │
│  │  📞  Call (212) 555-0142        │  │
│  └─────────────────────────────────┘  │
│  ┌─────────────────────────────────┐  │
│  │  ✉️  Email — draft prepared     │  │
│  └─────────────────────────────────┘  │
│                                       │
│  DRAFTED MESSAGE                      │
│  ┌─────────────────────────────────┐  │
│  │ Hello, I'm interested in NCT05… │  │
│  │ I'm a 62-year-old woman with... │  │
│  │ Could you tell me whether I may │  │
│  │ be a candidate for pre-screening│  │
│  └─────────────────────────────────┘  │
│         Edit before sending ›         │
└───────────────────────────────────────┘
```

---

### 5.7 Saved & Profile

**Saved:** same cards as Matches, plus a "checked 2 days ago" line. In v2 this grows a change feed.

**Profile:** grouped list of what was entered, each row editable, plus About / Sources / Disclaimers and a "Delete all my data" action that actually works instantly.

---

## 6. Data Source

**ClinicalTrials.gov API v2** — free, no key, JSON.

> ✅ **Verified live 2026-08-14** (M0). All endpoints and parameters below confirmed working. See `trialhead-spike/NOTES.md` for the full report.

### Endpoints
| Purpose | Endpoint |
|---|---|
| Search | `GET /api/v2/studies` |
| Single study | `GET /api/v2/studies/{nctId}` |
| Field metadata | `GET /api/v2/studies/metadata` |

### Key parameters
```
query.cond           condition
query.term           free text
filter.overallStatus RECRUITING|NOT_YET_RECRUITING   (pipe-separated)
filter.geo           distance(LAT,LON,50mi)     ← most valuable param
filter.advanced      AREA[StudyType]INTERVENTIONAL   ← see below
fields               trim the payload, records are large
pageSize / pageToken cursor pagination
countTotal           true
sort                 @relevance | LastUpdatePostDate
```

**Filter to interventional studies.** Patients seeking treatment want interventional
trials; observational studies pollute results and carry no `phases` field. There is no
dedicated `filter.studyType` — use the advanced filter syntax above. Verified: 266 → 234
results for the NYC breast cancer query, with every remaining result carrying a phase.

### Fields to request
```
protocolSection.identificationModule.{nctId,briefTitle}
protocolSection.statusModule.overallStatus
protocolSection.descriptionModule.briefSummary
protocolSection.conditionsModule.conditions
protocolSection.designModule.{phases,enrollmentInfo,designInfo}
protocolSection.eligibilityModule.*        ← the blob lives here
protocolSection.contactsLocationsModule.{locations,centralContacts}
protocolSection.sponsorCollaboratorsModule.leadSponsor
protocolSection.armsInterventionsModule
```

### The critical shape

`eligibilityModule` gives **structured** `minimumAge`, `maximumAge`, `sex`, `healthyVolunteers`, `stdAges` — and **unstructured** `eligibilityCriteria`, one long string containing both inclusion and exclusion lists.

That string is the whole engineering problem. Everything in §7 exists to deal with it.

---

## 7. The Eligibility Parser

Three stages, **all deterministic in v1**. No model, no backend, no network beyond the ClinicalTrials.gov API itself.

> **Why no model in v1.** The model was never load-bearing for correctness. Per Principle 4, every criterion needing deep language understanding — lab values, performance status, staging, biomarkers — resolves to `ask` no matter what a model concludes. The criteria that actually produce a verdict (age, sex) come from *structured* API fields and need no parsing at all. So the model only ever bought nicer plain-language restatements: polish, not correctness. It returns in Phase 2 as progressive enhancement (§4).

**Stage 1 — structural split (deterministic).**
Locate inclusion/exclusion section headers, split on bullets, newlines, and numbered lists. Emit an ordered list of verbatim criterion strings each tagged inclusion or exclusion. *Measure this before writing any UI.*

**Built and measured in M1: 96% clean on a 45-study holdout of unseen conditions.**
1,743 criteria extracted across 95 studies; median 15 per study, max 52. Implementation in
`trialhead-spike/Sources/TrialheadSpike/Parser.swift`, ~200 lines, zero dependencies.

Header detection must be permissive — real variants include role-scoped
(`Daughter of Cancer Survivor Inclusion Criteria:`), parenthetical
(`Inclusion Criteria (All Participants):`), bulleted (`* INCLUSION CRITERIA:`),
cohort-scoped, and numbered-prefix forms — but anchored on a trailing colon or
end-of-line so prose doesn't false-positive. Four complications confirmed in real data:

- **Nesting is two levels deep**, not three as M0 estimated — measured across 95 studies.
  Parent plus one level of children covers everything. Flat splitting would shred
  arm-specific sub-criteria into unrelated fragments, so preserve the hierarchy and
  render children as expandable sub-rows. Indent *width* varies (2, 3, and 4 spaces all
  appear), so rank distinct indents per study rather than assuming a fixed step.
- **Some sponsors submit criteria on a single line**, using inline `\*` as separators
  instead of newlines (NCT07716176 — 22 criteria on two lines). Detect by counting
  escaped asterisks per line, masking `\*\*` bold first, and restore the breaks.
- **Escaped markdown appears literally** — `\-`, `\*\*`, `\[`, `\]`. Unescape before display.
- **Comparators are Unicode** — `ECOG PS ≤ 2`, `Age ≥ 18`. Regexes need `≥ ≤` alongside ASCII.
- **Header variants** — `Key Inclusion Criteria:`, `Main Study Inclusion Criteria:`,
  no-colon forms, and cohort-scoped headers (`Inclusion Criteria for Cohort 3:`).

**Stage 2 — categorization (deterministic, rules).**
Classify each criterion by keyword and numeric pattern matching. Roughly 200 lines of pure Swift, no dependencies.

```swift
struct CategorizedCriterion {
    enum Category { case age, sex, diagnosis, stage, priorTherapy,
                         labValue, performanceStatus, comorbidity,
                         pregnancy, consent, other }
    let category: Category
    let verbatimText: String     // always shown; never discarded
    let polarity: Bool           // must have / must not have
    let matchedProfileTerms: [String]   // drug/condition names found in profile
}
```

Rules needed, in order of value:
- **Drug/therapy name matching** — string containment against the profile's medication and prior-treatment lists, case-insensitive, with common suffix handling
- **Numeric thresholds** — `≥ ≤ < > =` plus ASCII equivalents, with units
- **Category keywords** — "ECOG", "performance status", "pregnan", "informed consent", "creatinine", "hemoglobin", etc.
- **Everything unmatched** → `other`, which renders amber

Note that `age` and `sex` bypass this entirely: they come from `eligibilityModule.minimumAge` / `.sex`, already structured.

**Deferred to Phase 2 — plain-language restatement.** An on-device model (Apple Foundation Models, or a portable runtime if Android happens) rewrites each row into plainer English. Progressive enhancement only: where unavailable, rows show verbatim text, which Principle 2 requires anyway. **Correctness must never depend on it** — that constraint is what keeps v1 shippable and the app portable.

**Stage 3 — evaluation (deterministic).**
Match the normalized criterion against the profile. Pure Swift, fully unit-testable, no model involved. Returns `match / ask / blocker / unknown`, with `unknown` rendering as `ask`.

Only `age`, `sex`, and exact `priorTherapy` name matches may produce a `blocker`. Everything else caps at `ask`. Lab values and performance status are always `ask` — the user doesn't have those numbers memorized.

**Versioning:** store `parserVersion` on every parse so a parser change invalidates cached results.

---

## 8. Data Model

```swift
// Single instance, on-device only
Profile
  conditions: [Condition]        // controlled vocabulary
  birthYear: Int?
  sexAtBirth: Sex?
  location: CLLocationCoordinate2D?
  travelRadiusMiles: Int         // default 50
  priorTreatments: [String]
  currentMedications: [String]
  updatedAt: Date

TrialSnapshot
  nctId: String                  // primary key
  rawJSON: Data                  // full record, for re-parse
  etag: String?
  fetchedAt: Date
  briefTitle, briefSummary, leadSponsor: String
  overallStatus: Status
  phases: [Phase]?               // ⚠️ absent on observational studies
  studyType: StudyType
  conditions: [String]
  minimumAge, maximumAge: AgeBound?  // ⚠️ API returns "18 Years"/"6 Months",
                                     //    not integers. Parse value + unit.
  sex: Sex?
  enrollmentCount: Int?

Site
  nctId: String                  // FK
  facility, city, state, country: String
  coordinate: CLLocationCoordinate2D?
  status: Status
  contactName, contactPhone, contactEmail: String?

ParsedCriterion
  id: UUID
  nctId: String                  // FK
  kind: .inclusion | .exclusion
  verbatimText: String           // NEVER discard this
  normalized: NormalizedCriterion?
  parserVersion: Int
  orderIndex: Int

CriterionEvaluation
  criterionID: UUID              // FK
  profileVersion: Int
  verdict: .match | .ask | .blocker | .unknown
  rationale: String              // "You entered 62"

SavedTrial
  nctId: String
  savedAt: Date
  note: String?
```

Cache `rawJSON` so a parser improvement can re-run against stored records without refetching.

---

## 9. Tech Stack

| Layer | Choice | Note |
|---|---|---|
| UI | SwiftUI | |
| Concurrency | async/await, actors | |
| Persistence | SwiftData | GRDB if you want more control / FTS |
| Networking | URLSession + custom client | ETag caching, no third-party deps |
| Maps | MapKit | `Map` + `Annotation`, clustering |
| Criteria parsing | Pure Swift, regex + keyword rules | no model, no backend (§7) |
| Testing | Swift Testing | parser gets the real coverage |
| Min target | free to pick — no Apple Intelligence requirement | |

Deliberately zero third-party dependencies. For a portfolio project, "I wrote the API client" reads better than "I added Alamofire."

### Platform

**v1 is iOS-only** — a scheduling choice, not an architectural lock-in. One excellent platform beats two mediocre ones for a portfolio, and the interesting engineering here is the parser, which cross-platform work doesn't make more impressive.

Because v1 has no model and no backend, the entire logic layer — splitting, categorization, evaluation, API client — is plain deterministic code. If Android becomes worthwhile, **Kotlin Multiplatform** fits almost perfectly: share all of that, write SwiftUI and Compose UIs on top. Flutter also works.

Worth knowing and being able to say: Android holds roughly 40–45% of the US market and considerably more globally, skewing toward lower-income users. For an app premised on health access equity, iOS-only is a genuine limitation.

To keep the door open at no cost, keep the parser and evaluator in a module with **no UI framework imports** — pure Swift, no SwiftUI, no UIKit. That is good structure regardless and makes any future port mechanical rather than archaeological.

---

## 10. Build Order

Each milestone should end with something runnable.

- [x] **M0 — Prove the API.** ✅ *Done 2026-08-14.* `trialhead-spike/` — SwiftPM CLI with Codable models, API client, and fetch/search/dump commands. Every §6 parameter verified live. Findings in `trialhead-spike/NOTES.md`; three corrections applied to this doc.

- [x] **M1 — Parser spike.** ✅ *Done 2026-08-14.* **96% clean on a 45-study holdout** of unseen conditions (100% on the 50-study train corpus, but that's overfit — 96% is the real number). 1,743 criteria extracted across 95 studies. `Parser.swift`, ~200 lines, no dependencies. Full results in `trialhead-spike/NOTES.md`.

- [x] **M2 — Categorisation and verdicts.** ✅ *Done 2026-08-14.* Stages 2 and 3 built and measured: `Profile.swift`, `Categorizer.swift`, `Evaluator.swift`. **Key finding: 13.5% green / 86.5% amber / 0% red from text.** Red verdicts work but come only from the structured age/sex fields. This changes the card design — see §5.2. Full results in `trialhead-spike/NOTES.md`.

- [x] **M3 — Skeleton app.** ✅ *Done 2026-08-16.* `Trialhead/` — runs on the iPhone simulator against live data. Results list, trial detail with working checklist, profile settings. All six logic files compiled in **unchanged**, validating the no-UI-imports rule in §9. Two findings: site coordinates are city-level (see §5.2), and sub-headings were inflating question counts (fixed).

- [~] **M4 — Make it usable for real.** *Rewritten 2026-08-16; the original line predated M3.* In priority order:
  1. [x] **Persist the profile.** ✅ `LocalStore.swift` — one JSON file in the app sandbox, written on every change via `didSet`. Also carries search settings and saved trial IDs, plus a working "Delete everything". Verified by writing a state file into the simulator and confirming it loads.
  2. [x] **Contact sheet (§5.6).** ✅ `ContactSheet.swift` — site and central contacts (deduplicated — the same coordinator is routinely listed twice), tap-to-call, and an editable drafted message built from the profile and the top amber criteria. Reached by a prominent button placed *above* the checklist, since burying it under forty rows would mean nobody gets there.
  3. [x] **Saved trials (§5.7).** ✅ `SavedView.swift` + bookmark toggle. Saved trials are re-fetched **by ID**, not filtered from the current search, so they survive changing what you search for.
  4. [x] **Search area controls.** ✅ `LocationSheet.swift` + `LocationResolver.swift`. Three filters: search by **ZIP code**, search by **city**, and a **travel radius slider capped at 30 miles**. ZIP/city are turned into coordinates on-device by Apple's geocoder — the query never travels with any health detail. Reached from a labelled row at the top of the results list, not just a toolbar icon.

     **The 30-mile cap is a product decision, not a technical limit.** Trials commonly need weekly in-person visits, and travel is among the most common reasons people drop out. Listing something 200 miles away pads the results with places nobody will realistically keep driving to.

  5. [ ] **Sites map (§5.5)** with per-site contacts. Contacts are done; the map isn't. **M4 data check found per-site contacts are rare** — 5 of 85 sites in one trial, 0 of 18 in another — so the central contact carries the load and this is lower value than assumed.

  6. [x] **Nearest-site status bug.** ✅ *Fixed 2026-08-16.* `nearestSite` now prefers an **enrolling** site outright, however much closer a closed one is, and falls back to a closed one only when nothing else exists — flagged in amber on both the card and the detail screen. Site counts now describe enrolling sites ("nearest of 82 enrolling sites"), not every site ever listed.

     Demonstrated on NCT06545942 from Myrtle Beach, SC: the closest site is **0 mi and COMPLETED**, the closest enrolling one is **369 mi away in Lake Mary**. Before the fix the app put this trial top of the list as a local option; now it correctly sinks to the bottom.
  5. [ ] **A stronger card differentiator** — unresolved since M3, when distance turned out to be city-level. Needs a decision, not just code.

  ~~Deferred to M5: the first-run onboarding flow.~~ **Built 2026-08-16** — `OnboardingView.swift`, see §5.1.

- [ ] **M5 — Real-world hardening.** Empty/loading/offline/error states, VoiceOver, Dynamic Type, disclaimers, delete-my-data. *Two days.*

- [ ] **M6 — Five real users.** Watch someone use it without helping. Write down every place they hesitate.

Then v2: notifications, PDF export, multi-profile.

---

## 11. Open Questions

1. **Condition vocabulary.** Free text produces bad queries ("stage 4 breast cancer" won't match well). Options: MeSH terms from `derivedSection.conditionBrowseModule`, or scrape a condition list from the API and bundle it. *Decide in M2.*

2. ~~**Foundation Models availability.**~~ **Closed 2026-08-14.** v1 ships rules-only, so there is no device requirement and no fallback path to maintain. Revisit when Phase 2 adds plain-language restatement — and only as progressive enhancement.

3. **How much profile is too much?** Every field improves matching and costs a user. Prior treatments are the highest-value/highest-friction field. Consider making them optional with an inline explanation of what they unlock.

4. **International.** v1 is US-only for distance and phone formats. Non-US sites still display; just don't over-promise.

5. **Rate limits.** Unknown. Cache aggressively and back off politely regardless.

6. **Ranking.** Naive v1: relevance from the API, then distance ascending, blockers last. Revisit after M6.

7. ~~**Multi-cohort trials.**~~ **Closed 2026-08-14 (M1) — option (a).** Measured at ~4% of studies (3 of 50 train, 1 of 45 holdout), rarer than feared. Detect multiple cohort-scoped blocks, render all of them behind a banner: *"criteria vary by treatment group — review with your care team."* Cheap, honest, and doesn't ask a layperson to self-assign to a treatment arm.

8. **Parse-failure fallback.** *(new, from M1)* ~2–4% of studies can't be split by rules — some sponsors submit criteria as unstructured prose with no bullets or line breaks (NCT05685368). **Required v1 behavior:** detect the failed parse and fall back to showing verbatim criteria text with a note — *"we couldn't break this study's criteria into a checklist; here is the original text."* Never render an empty or half-built checklist. See §5.4.

---

## 12. Safety & Compliance

- **Copy audit.** No screen may say "eligible," "qualified," or "you match." Approved vocabulary: *likely*, *to ask*, *may be a candidate*, *bring this to your care team*.
- **Provenance.** Every trial screen shows source and retrieval date.
- **Disclaimer** on first launch, on trial detail, on the checklist. Persistent, not dismissible-forever.
- **Privacy.** No health data off-device. No analytics on health fields. Working delete-everything action. If a backend is ever added, this section gets rewritten first.
- **App Store.** Review guidelines 1.4.1 and 5.1.1 cover medical apps and health data. Read them before submitting.
- **Not a medical device.** The app displays public information and helps organize questions. It does not diagnose, treat, or recommend. Keep it that way — the line is crossed by *scoring* patients, not by *showing* them criteria.

---

## 13. The Resume Angle

The interview answer this project is built to produce:

> "Eligibility criteria come back as unstructured clinical prose, so I built a three-stage parser — splitting, categorisation, then evaluation against a profile stored only on the device. It splits 96% of studies cleanly, measured on a holdout set of conditions I hadn't tuned against.
>
> The interesting part was what the measurement told me. Only about 13% of rules could be resolved from what a user can reasonably be asked to type — the rest need bloodwork or clinical judgement. My original design had a fit-score badge on every search result, and that number killed it: every trial scored roughly the same, so the badge looked informative but couldn't distinguish anything. I replaced it with travel distance and a question count, and reframed the whole app from an eligibility calculator into a preparation tool. That's more honest and, I think, more useful — the step most patients never take is picking up the phone."

That's a systems answer, a measurement answer, and a product answer in one. The strongest part is killing your own feature because the data said so — most portfolio projects have no evidence that anything was ever reconsidered.

Two more things worth being able to say: *"here's where the parser still fails and why I shipped it anyway"* (~2–4% of studies are unstructured prose, and they fall back to verbatim text), and *"I caught a flaw in my own measurement"* (the first verdict run scored a breast-cancer profile against diabetes trials).

---

## Tomorrow

Start at **M0**, then **M1**. Don't open Xcode's UI editor until the parser spike tells you whether the core idea holds.
