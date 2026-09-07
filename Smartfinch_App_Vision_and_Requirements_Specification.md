# Bird Collecting App — Vision & Requirements Catalogue

**Date:** 4 September 2026 · **Audience:** children aged 8–13 · **Platform:** Flutter (Android + iOS) · **Operation:** fully offline and local
**Basis:** a fork of **BirdNET Live v1.1.2** · **Revised:** 4 September 2026, against the actual codebase

---

## 0. About This Document

The document has three parts. The **Vision** (chapter 1) defines what the app is for and what decisions are measured against. The **Scoring System** (chapters 2–3) is the heart of the product and is therefore worked out in detail, with concrete numbers and a sanity check. The **Requirements Catalogue** (chapters 4–6) lists everything buildable, with an ID, a priority and an acceptance criterion.

### Revision note

This version has been checked against the BirdNET Live codebase it will be built on. Requirements that turned out to be **already built** are marked ✅ with a note; requirements that turned out to be **harder than assumed** carry a ⚠️.

**Decisions taken during the review** (each is marked *Decided* at the requirement it affects):

| Subject | Decision | Requirements touched |
|---|---|---|
| Non-bird species | All 862 amphibians, mammals and insects stay collectable; the Collection filters by group | new `SAM-17` |
| Species images | Used exactly as the original app uses them. Silhouettes are **not in the MVP** — the placeholder contrast carries it, per-species silhouettes follow in P1 | `SAM-04`, new `SAM-04b` |
| Spectrogram | Kept at full size — it is a teaching surface, and the scoring UI is laid out around it | `LIVE-01` |
| Spoken announcements | Unchanged, default off, still naming the species | new `LIVE-17` |
| Maps and places | Maps kept; the child names their own places, editable afterwards | new `LOG-13`, `LOG-14`, `KID-07` |
| Audio clips | BirdNET Live's logic kept, with a retention rule in Settings | `LIVE-14`, new `SET-12` |
| Weather | Kept, behind its consent toggle | `AUS-11` |
| Collection vs. Explore | Two separate areas, not one toggle | `SAM-02`, `SAM-16`, `HOME-04` |
| Settings | Reorganised behind *Advanced*, not cut back; expert inference controls deleted | `SET-01`, `SET-08` |
| Sharing and backup | Split: full backup for parents, one day image for sharing | `SET-07`, `LOG-11` |
| Background recording | **Rescued** — extracted into its own module before Survey is deleted, unwired for the MVP | `LIVE-10`, `LIVE-11` — both **kept at P1** |
| File analysis, ARU, Point Count, voice memos | Removed | — |

**Decisions on the MVP specification gaps** (chapter 9): **a species with no local rarity level scores nothing** — the off-list rule in 2.3 is removed and `geoExclude` stays the default filter (`PKT-11`, `PKT-18` both to P2; `geoAdaptive` documented as a future option) · a detection scores **the moment it is shown**, with peak confidence written back on close (`PKT-15`) · the **confidence slider governs the points** and stays adjustable through the MVP, so the applied threshold is frozen per event (`PKT-15`) · **one shared rarity scale for all animal groups** (`SAM-17`) · the **home region is chosen during onboarding** (`SET-09` raised to P0, `KID-01`).

> **The one consequence to keep in view:** removing the off-list case takes the sharpest seasonal signal out of the point value. Week coupling still works, but through rank shift alone, which is the damped mechanism (2.2). **The year list — `PKT-12`, `SAM-16`, `AUS-13` — is now the main way a child experiences the year changing**, and should be built earlier than its P1 position suggests.

**One further decision, and it is the one that makes the adjustable settings shippable:** the detection parameters stay reachable in Advanced settings, but **the whole scoring layer pauses while they sit outside the scoring range** — stars, collection, life list, year list and badges alike. New `PKT-20`, with the warning in `SET-13`, the live indicator in `LIVE-18`, the journal entries in `LOG-15` and the data-model rules in `DAT-11`. Detection itself keeps running and the recordings are kept, so experimenting costs nothing except the score for that stretch.

**A fourth pass read chapters 2–6 against each other** and found **twelve conflicts**, listed at the end of chapter 9. **Four are settled:** levels now **ratchet** (a recomputation may raise a level, never lower one), the level titles were renamed so achievements and levels no longer share names, an **active day** is one that produced at least one scoring detection, and a test-mode day therefore does not extend a streak — which `SET-13` now states at the moment the setting is changed. The remaining eight are two badges that lost their definition with the off-list case, two fairness problems in the weekly badges, one data-model rule to reuse, and three editorial fixes.

**Other substantive changes:**

- **2.1** now describes how the existing app actually derives a rarity level — six levels, week-accurate, but **rank-relative rather than absolute**. **2.2**, **2.9**, **2.10** and the risk table follow from that. This is the most important change in the revision: it does not overturn week coupling, but it changes its shape.
- **DAT-06** (ship precomputed range data) is **already solved** by the bundled geo model, and solved better. **DAT-10** is new and replaces it: one shared, cached level scale for the whole app.
- **DAT-01** is larger than it reads: there is no database of any kind today.
- **SET-01** is reversed: settings are reduced, not preserved.
- **LIVE-10/11** carry a warning — the only working background-recording code lives in a module being deleted.
- A new phase **P-1** is added to chapter 7: removing the inherited research modes before any Smartfinch feature is built.

The companion document **`BirdNET_Live_to_Smartfinch_Transition.md`** holds the full inventory: a keep/change/remove verdict per module, line counts, the persistence migration, and the upstream-merge strategy.

### Language convention

The app ships in German. Throughout this document, user-facing labels are given in English with the **German string that actually appears in the app** in parentheses:

> **Live Mode** (`Live-Modus`) · **Stars** (`Sterne`) · **My Collection** (`Meine Sammlung`)

Badge, achievement and level names are product copy, so the German version is authoritative and the English is a gloss for readers of this document.

### Priority levels

| Level | Meaning | Guiding question |
|---|---|---|
| **P0** | **Prototype / MVP** | Without this you cannot find out whether the game mechanic works at all. Goal: a child keeps playing voluntarily for two weeks. |
| **P1** | **Version 1.0** | Needed for the app to be publishable and to feel finished. |
| **P2** | **Version 1.x** | Depth, breadth, long-term motivation. After the first real user feedback. |
| **P3** | **Vision / later** | Directional decisions that only need the architecture kept open today. |

### ID scheme

`AREA-nn` — e.g. `PKT-04`. The area codes keep their German mnemonics so that references stay stable across both language versions of this document:

| Code | German | English meaning |
|---|---|---|
| `LIVE` | Live-Modus | Live mode |
| `PKT` | Punkte | Scoring |
| `AUS` | Auszeichnungen | Badges & achievements |
| `STAT` | Statistik | Statistics |
| `SAM` | Sammlung / Erkunden | Collection & explore |
| `LOG` | Tagebuch / Verlauf | Journal & history |
| `HOME` | Startseite | Home screen |
| `AVA` | Avatar | Avatar |
| `SET` | Einstellungen | Settings |
| `KID` | Kindgerechtigkeit | Child-appropriateness |
| `DAT` | Daten & Architektur | Data & architecture |
| `NFA` | Nicht-funktionale Anforderungen | Non-functional requirements |
| `IDEE` | Weiterführende Ideen | Further ideas |

### Already built (starting point)

Smartfinch is a fork of **BirdNET Live v1.1.2** (158 Dart files, ~78,800 lines). The starting point is considerably richer than a prototype, and in places richer than this document originally assumed. The full inventory, and what happens to each part, is in the companion document **`BirdNET_Live_to_Smartfinch_Transition.md`**; the summary is:

**Directly reusable:**

- **BirdNET AI runs locally on the device** — BirdNET+ classifier, 9,789 species, ONNX in a background isolate
- **The geo model at weekly resolution** — a 13.6 MB ONNX model taking `[latitude, longitude, week]` and returning a per-species probability for **any of 48 weeks, anywhere on Earth**. `predictAllWeeks()` produces the full annual curve per species in one pass. This is what the whole scoring system in chapter 2 stands on, and it is already there (see `DAT-06`)
- **Six rarity levels**, week-accurate and location-adaptive (`ExploreTier`: `rare` · `scarce` · `uncommon` · `frequent` · `common` · `abundant`) — see 2.1 for what "adaptive" means and why it matters
- **Live mode**: running spectrogram plus a list of currently detected species, with confidence
- **Explore**: location-based species list sorted by frequency, already-detected species ticked, taxon filters, search, and a `detected / undetected / all` filter — which is most of `SAM-02` already
- **A life list** — a persisted lifetime set of every species ever detected, with a backfill from existing data. This is `PKT-04`'s first-find check, already shipping
- **Sessions**: detections grouped per recording, with export, audio playback and an HTML report
- Fully offline operation, foreground-service background recording, 12 UI locales, offline species descriptions in 11 languages, a 12.7 MB taxonomy with names, families and Wikipedia links

**Present, but being removed** (see the transition document, §3.3): Survey mode, ARU mode, Point Count, File Analysis and Batch Analysis — roughly 20,000 lines of research tooling that has no place in a children's app.

**Not present at all, and larger than it looks:**

- **There is no database.** Persistence today is one JSON file per session plus 129 preference keys. No schema, no migrations, no unique constraints, no queries. `DAT-01` is therefore not a choice of database — it is the introduction of one
- No scoring, no badges, no achievements, no levels, no avatar, no statistics
- **No species images.** The image directory contains one hand-crafted fallback; real images are generated by a separate pipeline and are not in the repository
- The species texts that do exist are written **for adults** — `SAM-11` is a rewrite, not a translation

---

## 1. Vision

### 1.1 Product vision

> **Every child has a world of birds outside their front door — they just don't hear it.**
>
> This app turns listening into a collecting game. Listen to the birds, collect stars, fill your species book, and after a few weeks you realise there aren't "a few birds" out there but forty different voices. What you end up with is not a high score, but a child who can tell a blackbird from a song thrush — **because learning that was fun.**

**The guiding metric is species count, not screen time.** A good week is one in which a child got to know three new species — not one in which they spent a long time in the app. Every design decision is measured against this.

### 1.2 Audience & usage context

**Primary: children aged 8–13.** They can read, they understand rules, and they know collecting mechanics from trading cards and video games. They want to be taken seriously, not babied — a "chick" aesthetic is fine, baby talk is not.

**Secondary: accompanying adults** (parents, grandparents, group leaders). They install the app, sit next to the child at first, and are often the most curious of all. They don't need their own mode in v1, but the app must not bore them.

**Typical situations:**

| Situation | Duration | What matters |
|---|---|---|
| At the window or in the garden, after school | 10–30 min | Start instantly — one tap on the icon, spectrogram running |
| Walk to school, walk in the park | 20–60 min | Keeps running in a pocket; battery; no interaction needed |
| Weekend trip, forest, lake | 1–3 h | Many new species at once — the big payoff |
| In bed in the evening | 5 min | Browse the collection, look at points, make plans |

The last case matters most for retention: **the app has to be fun even when no bird is singing.** That is the job of the collection, the points overview and the badges.

### 1.3 The core loop

```
    Go outside and listen
             ↓
   BirdNET detects a species  ──→  Live card shows: name + stars earned
             ↓
   New? → confetti + a small species card  ("That's a wren!")
             ↓
   Stars land on the counter at the top, the collection gets a tick
             ↓
   Evening: daily total, chart, maybe a new badge
             ↓
   "I only need one more tit species" ──→  Go outside and listen
```

The loop has three reward rhythms that deliberately operate at different speeds:

- **Seconds** — the detection itself: name, stars, animation
- **Days** — daily total, variety bonus, daily badges
- **Weeks to months** — the collection filling up, achievements, levels

### 1.4 Design principles

These seven sentences settle the hard cases:

1. **There is never a punishment.** Points are never deducted, streaks end without blame, there are no countdown timers and no "You haven't done anything today!". Duolingo-style streak anxiety is a documented problem with children — we take the collecting mechanic, not the pressure.
2. **The bird is the star, not the number.** When the score and the species name compete for attention, the species name wins.
3. **Common species stay valuable.** A child with a balcony in the inner city must make visible progress. The spread between the commonest and the rarest species is deliberately compressed to a factor of 20 instead of the real factor of 1000.
4. **Curiosity is rewarded, not runtime.** Points are awarded per species per day, not per minute. Leaving the phone running for hours achieves almost nothing; going somewhere new achieves a lot.
5. **Offline and account-free.** No login, no registration, no cloud, no ads, no tracking. The app works in a dead zone in the woods — exactly where it is needed.
6. **Every number is explainable.** Tap any points award and see how it was calculated. Children do check the maths, and if the numbers look arbitrary they stop trusting them.
7. **Nothing interrupts the listening.** No animation, no popup and no level-up may block live mode or cause the next bird to be missed.

### 1.5 Positioning

| App | What it is | What we do differently |
|---|---|---|
| **Merlin Bird ID** | An identification tool for interested adults | We don't just identify, we reward. Audience is a child, not an adult. |
| **BirdNET app** | A scientific recording tool | We are a game with a learning effect, not a reporting portal. |
| **Pokémon GO** | Collecting fictional creatures, location-bound | Our creatures are real and actually present right now. No fantasy content, no pay-to-win. |
| **Duolingo** | Daily practice with streaks and leagues | We take streaks and collecting, but without punishment, leagues or push pressure. |

### 1.6 Non-goals

- **No in-app purchases, no ads, no loot boxes.** Not in v1 and not later.
- **No endless recording as a points source.** Leaving the device running overnight must never be a viable strategy.
- **No scientific claim.** BirdNET is sometimes wrong; the app does not sell its detections as facts and encourages the child to go and look.
- **No location sharing with third parties.** The location never leaves the device.

---

## 2. The "Stars" Scoring System

The currency is called **Stars** (`Sterne`) and is shown as a number with a star symbol (`⭐ 12,480`).

> **Avoid a naming collision:** a species' *rarity* should **not** also be shown as stars, or children will confuse "this species is 3 stars rare" with "I earned 3 stars". Recommendation: show rarity as a **coloured badge with a name plus feathers** (🪶) and points as **stars**. Two symbols, two meanings, no confusion.

### 2.1 Where rarity comes from

**Rarity levels are not redefined here.** The BirdNET Live app this is built on already has frequency levels integrated, and those are taken as they are (decision **D3**). The scoring system simply reads the level off.

Underneath sits BirdNET's **range (meta) model**: for every combination of latitude, longitude and **calendar week** it returns a value from 0–100 per species. That value is the eBird checklist frequency — the percentage of checklists submitted for that location in that week that contain the species. A great tit in Chemnitz sits at 99 all year; a house martin moves from 0 to 12 to 40 and back over the course of the year.

**Identifiers:** `f_week` = frequency for the location and the current calendar week. `f_year` = maximum across all 48 weeks (no longer needed for scoring, but used for the annual cycle bar in SAM-15).

#### How the existing app turns `f_week` into a level — and why it matters

This is the one place where the existing implementation differs from what a reader of this chapter would assume, so it is spelled out rather than left implicit.

The app has **six levels**, and the boundaries between them are **not fixed frequency thresholds**. They are **rank percentiles, recalibrated for every location and every week**. All species scoring above an inclusion threshold of `0.03` are sorted, and the list is cut at fixed shares:

| Level | Share of the local list | Points (see 2.3) |
|---|---:|---:|
| Abundant (`Sehr häufig`) | 8 % | 50 ⭐ |
| Common (`Häufig`) | 12 % | 100 ⭐ |
| Frequent (`Regelmäßig`) | 25 % | 200 ⭐ |
| Uncommon (`Gelegentlich`) | 28 % | 350 ⭐ |
| Scarce (`Selten`) | 17 % | 600 ⭐ |
| Rare (`Sehr selten`) | 10 % | 1,000 ⭐ |

Two gentle absolute floors (raw score 0.20 for Abundant, 0.10 for Common) stop a species-poor area from promoting its best guess past what the score justifies.

**Three consequences follow, and all three are load-bearing:**

1. **A level is always relative to the child's own surroundings.** An inner-city child's "Rare" is the rarest tenth of *their* local list, not a nationally rare bird. This is **principle 3 enforced automatically** — the balcony child and the forest-edge child both have 1,000-star species within reach. It is the strongest argument for taking the existing levels as they are.
2. **The number of species at each level does not change over the year.** Roughly 10 % of locally present species are "Rare" in every single week. The seasons move species *between* levels; they do not change how many expensive birds exist.
3. **Seasonality therefore works through rank shift, not through absolute frequency** — and, since the off-list case was removed in 2.3, rank shift is the only mechanism inside the point value. See 2.2.

### 2.2 Week coupling — the central decision

> **A species' points follow its rarity in the current calendar week, not an annual average. They therefore change over the course of the year — and that is intentional.**

Why this is the right call: a barn swallow in June is an everyday bird, in March a small sensation and in January a big one. A scoring system that treats all three the same throws away exactly what makes birdwatching interesting — **that the world outside changes every few weeks.** With week coupling, a child picks up phenology along the way: who arrives when, who leaves when, who stays.

**What this looks like in practice** (frequency values illustrative, 6-level mapping):

| Species | Peak season | Points | Off season | Points | Factor |
|---|---|---:|---|---:|---:|
| Blackbird (`Amsel`) | May, `f=60` → L1 | 50 ⭐ | January, `f=45` → L1 | 50 ⭐ | ×1 |
| Starling (`Star`) | May, `f=35` → L2 | 100 ⭐ | January, `f=8` → L3 | 200 ⭐ | ×2 |
| Blackcap (`Mönchsgrasmücke`) | May, `f=30` → L2 | 100 ⭐ | January, `f=0.5` → L5 | 600 ⭐ | ×6 |
| Barn swallow (`Rauchschwalbe`) | June, `f=25` → L2 | 100 ⭐ | March, `f=2` → L4 | 350 ⭐ | ×4 |

Resident birds stay stable, migrants swing hard. Exactly right — the blackbird is always there, the swallow is not.

> **Read the table as direction, not as arithmetic.** The figures above were worked out assuming fixed frequency bands. Because the app's levels are rank-relative (2.1), the *direction* of every row holds — a blackcap in January really does land in a rarer level than a blackcap in May — but the exact factor depends on how much the rest of the local list thinned out in the same week. Where a whole winter list shrinks together, a species can hold its rank and its points. **The seasonal swing is real but damped relative to this table**, and the size of the damping is a measurement, not a guess: see the open question at the end of 2.10.

**Where seasonality actually comes from, under the app's levels:**

| Mechanism | Strength | What the child sees |
|---|---|---|
| **Rank shift within the list** | Moderate | A migrant that thins out drops one or two levels. The everyday case, mild and continuous — **and, after the decision in 2.3, the only mechanism inside the point value itself** |
| ~~Off-list spike~~ | — | *Removed.* A species not on this week's list has no level and scores nothing (2.3) |
| **The year list** | Strong, but different in kind | Not a higher point value — a *second collection* that empties every January. The year-first multiplier (`PKT-12`), the "This year" view (`SAM-16`) and the year achievements (`AUS-13`) |

**Read this honestly:** with the off-list case gone, the point value alone carries less of the seasonal story than chapter 2 originally claimed. A blackcap in January is worth more than in May, but by one or two levels rather than six — and only to the extent that the rest of the local list did not thin out with it.

What still makes the year visible to a child is the **year list**: in January every returning species is a *Jahresneuling* again, worth double, and the "This year" collection starts from zero. That is a strong, legible seasonal rhythm — it simply lives one layer up from the point value. `PKT-12`, `SAM-16` and `AUS-13` are therefore no longer just the safety net against the motivation drop; they are the main way the app shows that the world outside changes. Treat them as P1-early, not P1-late.

The annual cycle bar (`SAM-15`) and the season hint (`PKT-17`) keep their full value here. They teach phenology *directly* — "here it is present, here it isn't" — and they no longer have to explain a large swing in the numbers, only a modest one.

**Two rules without which this does not work:**

1. **Freeze it in the journal.** The point value is determined at the moment of detection and **written into the `ScoreEvent` permanently**. It is never recalculated afterwards. Otherwise a child's history would silently rewrite itself — that May outing would suddenly be worth more in December. (See DAT-03: a recomputation may re-derive multipliers and bonuses, but must never touch the stored base value.)
2. **Make it visible, don't hide it.** The changing values have to be communicated everywhere or they look arbitrary. Concretely: SAM-03 ("This week: 200 ⭐"), SAM-15 (annual cycle bar), PKT-17 (season hint on the detection card), SET-11 (a dedicated section "Why do the points change?").

### 2.3 Mapping levels to points

Because the number of rarity levels comes from the existing app, what is fixed here is not the banding but the **mapping rule**:

> The commonest level is worth **50** stars, the rarest **1,000**. Everything in between is distributed geometrically — a constant factor per level.

**The existing app has six levels, so the six-level row is the one that applies.** The other rows are kept only so the rule survives a future change to the level count.

| Number of levels | Factor | Points per level (common → rare) |
|:---:|:---:|---|
| 4 | 2.71 | 50 · 150 · 350 · 1000 |
| 5 | 2.11 | 50 · 100 · 200 · 450 · 1000 |
| **6** ← *in use* | **1.82** | **50 · 100 · 200 · 350 · 600 · 1000** |
| 7 | 1.65 | 50 · 80 · 150 · 250 · 400 · 600 · 1000 |

*(All worked examples in this document use the 6-level row.)*

**Why a 1 : 20 spread and not 1 : 1000?** A hoopoe really is a thousand times rarer than a blackbird. In the game it may only be worth twenty times as much, or a child with an inner-city courtyard feels shut out (principle 3). This compression is the most important balancing decision after the once-per-day rule.

**Species that are not on this week's local list score nothing.** *Decided — this replaces the earlier rule that gave them the top level and full points.*

The rule is one sentence: **no rarity level, no stars.** A species below the geo-model's inclusion threshold has no level, so there is nothing to look up and nothing to award. The app's default species filter (`geoExclude`) already removes those detections before they reach the screen, so in practice the case is invisible — but the rule is written in terms of the *level*, not the filter, so it stays correct if the filter mode is ever changed.

Three reasons this is the better rule:

1. **The most expensive points went to the least reliable detections.** A house martin in January is far more likely to be a false positive than a house martin; rewarding it with 1,000 stars pointed the whole incentive at BirdNET's weakest moments. That was the main risk in 2.9, and this removes it at the root rather than defending against it.
2. **What the child sees is what the child can collect.** No hidden category, no species that exists in the rules but never on screen, no confirmation dialog for an exception. One less thing to explain in SET-11.
3. **The ceiling stays where it belongs.** The rarest level of the *local* list is still worth 1,000 stars, and roughly a tenth of the locally present species sit there. The top of the ladder is reachable every day — it just has to be a bird that genuinely lives here.

> **What this costs — stated plainly.** The off-list case was the sharpest seasonal signal in the scoring system (2.2). Without it, week coupling works through rank shift alone, which is the damped mechanism. **The seasonal story therefore rests mainly on the year list from here on** — the year-first multiplier (PKT-12), the "This year" view (SAM-16) and the year-list achievements (AUS-13). Those three were the safety net against the motivation drop; they are now also the main carrier of "the year outside changes". Worth pulling forward in the plan (see 9, open question 5).

**A species detected but not on the local list** still belongs in the collection — it was genuinely heard, and principle 1 says nothing is taken away. It simply scores zero, exactly like the manually added species in LIVE-16.

### 2.4 When points are awarded at all

**Base rule: once per species per day.**

| Event | Points |
|---|---|
| **First** detection of species X on day D | full base points (× multiplier) |
| Every **further** detection of X on day D | **0** — the card shows "already collected today ✓" (`heute schon gesammelt ✓`) |
| Detection of X the next day | full base points again |

This is the single most important balancing rule: it makes **continuous running worthless and changing location valuable.** Two hours at the same window is worth exactly as much as ten minutes at the same window — but ten minutes at the edge of a wood is a different thing entirely.

**Day definition:** local calendar day 00:00–23:59 in the device timezone.
**Week definition:** ISO week, Monday to Sunday — used both for the loyalty rule and for the frequency lookup.

### 2.5 Multipliers

| # | Name | Condition | Factor | Prio |
|:---:|---|---|:---:|:---:|
| M1 | **First find** (`Erstfund`) | species has **never** been detected before | **×3** | P0 |
| M2 | **Permanent guest** (`Dauergast`) | **6th** day within the week featuring this species | **×3** | P1 |
| M3 | **Year first** (`Jahresneuling`) | first time this species has appeared **this calendar year** | **×2** | P1 |
| M4 | **Regular** (`Stammgast`) | **3rd** day within the week featuring this species | **×2** | P0 |

**Stacking rule:**

> **Multipliers do not multiply with each other. Only the highest one applies.**

Without this rule a first find of a year first could yield 1000 × 3 × 2 = 6,000 stars and blow the curve apart. With it the maximum factor is **×3**, the maximum per species per day is **3,000 stars**, and the rule fits in one sentence for a child: *"The best bonus always wins."*

**Loyalty multiplier: 3rd day ×2, 6th day ×3** (decided). The rising shape (1, 1, **2**, 1, 1, **3**, 1) is better than two ×3 spikes because it builds towards the weekend instead of peaking mid-week. Share of weekly points: 28.3 % (worked out in 2.8).

> **Removed:** the season multipliers originally planned ("out of season", "surprise visitor") no longer exist. Week coupling replaces them — the higher value of a bird at the wrong time of year is now baked into the rarity level itself. An additional multiplier would count the same effect twice.

### 2.6 Additive bonuses

Bonuses are added **after** the multipliers and are never themselves multiplied. This is the inflation guard.

| # | Name | Condition | Bonus | Prio |
|:---:|---|---|---:|:---:|
| B1 | **Variety 5** (`Vielfalt 5`) | 5 different species in one day | **+50** | P0 |
| B2 | **Variety 10** (`Vielfalt 10`) | 10 different species in one day | **+150** | P0 |
| B3 | **Variety 15** (`Vielfalt 15`) | 15 different species in one day | **+300** | P1 |
| B4 | **Variety 20** (`Vielfalt 20`) | 20 different species in one day | **+500** | P1 |
| B5 | **Variety 25** (`Vielfalt 25`) | 25 different species in one day | **+750** | P2 |
| B6 | **Early riser** (`Frühaufsteher`) | first detection of the day before **09:00** | **+50** (1×/day) | P1 |
| B7 | **New place** (`Neuer Ort`) | detection in a 5 km cell never listened in before | **+200** (1×/day) | P2 |
| B8 | **Week wrap-up** (`Wochenabschluss`) | at least one detection on ≥ 4 days of the week | **+300** (1×/week) | P2 |

The variety bonuses are **cumulative**: reaching 15 species yields 50 + 150 + 300 = **500**. This creates a staircase through the day — something visibly happens at species 5, 10 and 15.

> **On B6:** with a 09:00 threshold this is no longer a rare feat but a **reliable morning reward** — every walk to school qualifies. For 8- to 13-year-olds that is the better choice than a 07:00 hurdle that is almost never reachable on a school day. The bonus is deliberately kept small at +50 so its frequency doesn't make it inflationary.

### 2.7 The formula

```
BasePoints(species X, day D) =
    point value of X's rarity level in the calendar week of D
    → frozen into the ScoreEvent

Points(species X, day D) =
    BasePoints  ×  max(all applicable multipliers, at least 1)

DayPoints(D) =
    Σ Points(X, D) over all species first detected on D
    +  Σ all applicable additive bonuses
```

**Worked examples** (6-level reference):

| Case | Calculation | Result |
|---|---|---|
| Blackbird, second time today | — | **0** ⭐ |
| Blackbird in May, first time today | 50 × 1 | **50** ⭐ |
| Robin, first find ever | 100 × 3 | **300** ⭐ |
| Great tit, 3rd day this week | 50 × 2 | **100** ⭐ |
| Great tit, 6th day this week | 50 × 3 | **150** ⭐ |
| Blackcap in May, first this year | 100 × 2 | **200** ⭐ |
| **Blackcap in January**, first this year | 600 × 2 | **1,200** ⭐ |
| Barn swallow in March, first find ever | 350 × 3 | **1,050** ⭐ |
| Hoopoe, first find, out of season | 1000 × 3 | **3,000** ⭐ |

The two blackcap rows show week coupling at its clearest: same bird, same rule, six times the value — because in January it has no business being here.

### 2.8 Balancing sanity check

**A normal day in the garden in May, 45 minutes, 14 species** (6 × L1, 6 × L2, 2 × L3 in that week)

| Item | Stars |
|---|---:|
| Base points (6×50 + 6×100 + 2×200) | 1,300 |
| Variety bonus (5 and 10 reached) | 200 |
| **Day total** | **1,500** |
| *the same day if it is the very first day (all ×3)* | *4,100* |

The same species mix in January would score considerably higher — but you would rarely gather 14 species then. Week coupling therefore evens out the seasons as a side effect: many cheap species in summer, few expensive ones in winter. That is a welcome property, because it carries the app through the winter.

**A week in which the same 8 garden birds are detected every day** (base 600/day + 50 variety bonus)

| Variant | Weekly total | Share from the loyalty multiplier |
|---|---:|---:|
| **3rd day ×2, 6th day ×3** *(decided)* | 6,350 ⭐ | 28.3 % |
| *without the loyalty multiplier (for comparison)* | *4,550 ⭐* | *0 %* |

**The same week with exploration** (4 garden days + 3 outings with 4 new L3 species each): **12,800 ⭐**

Exploring is therefore worth roughly **double** staying at home — clear enough to make outings attractive, but not so brutal that a child without a car feels left behind.

### 2.9 The risk of week coupling — and what helps

Week coupling has an uncomfortable property that must be understood before implementation:

> **The highest point values automatically go to the least likely detections — and those are precisely the detections BirdNET is most likely to get wrong.**

A "house martin in January" is most probably a false positive, yet it was to be rewarded with 1,000 stars. Without a countermeasure, the most profitable strategy would be to leave the phone running in poor conditions and wait for errors.

> **This risk has largely been designed out.** The decision in 2.3 — a species without a local rarity level scores nothing — removes the expensive end of it, and the default `geoExclude` filter means those detections never reach the screen in the first place. What remains is the ordinary case: a species that *is* on the local list, in its rarest tenth, misidentified. That is a much smaller problem, bounded at 1,000 stars, and it is the same false-positive rate the app already lives with today.
>
> The remedies below are therefore no longer load-bearing. They are kept because they remain good ideas — but the section's original alarm no longer applies.

Three remedies, ordered by effort:

| | Measure | Effect | Recommendation |
|:---:|---|---|---|
| **a** | **Confidence tiering** — the higher the point value, the higher the required detection confidence. For example: normal threshold up to 200 ⭐, a markedly higher one from 350 ⭐. | Hits the problem at its root and costs nothing in feel | **implement (P1, PKT-18)** |
| **b** | **Confirmation step** — for detections above a point threshold the app asks politely ("That would be something special! Did you see it too?"). Points are awarded either way, but the species is marked *unconfirmed* in the collection until it turns up a second time. | Honest, educational, no punishment | **implement (P1, PKT-11)** |
| **c** | **Damping** — the point value may exceed the species' best level of the year by at most two steps. A barn swallow (peak L2) would reach L4 in January, not L6. | The most effective cap, but costs some of the magic | **largely unnecessary — see below (P2, PKT-19)** |

Recommendation, revised: **(a) and (b) both drop to P2; (c) stays unbuilt.**

Two things happened to shrink this risk to a normal-sized one:

- **Levels are rank-relative** (2.1), so a marginal detection cannot climb arbitrarily high. The ceiling is 1,000 stars, and roughly a tenth of the local list sits there legitimately.
- **The off-list case scores nothing** (2.3), which removes the one path where a single false positive bought the maximum.

`PKT-18` (confidence tiering) is worth noting separately: the `geoAdaptive` filter mode already implements it precisely, calibrated across 20 locations and 4 seasons, on the same `ExploreTierScale` the scoring engine uses. **It is not the default mode and is not being switched on** — `geoExclude` stays (see gap A in chapter 9). But it means the requirement is one setting away if the field test shows false positives becoming a problem.

`PKT-19` (damping) drops from "hold in reserve" to "not needed". It stays in the catalogue only because keeping an option costs nothing.

### 2.10 Open balancing questions

- **Too generous at the start?** 4,100 stars on day one might make everything afterwards feel flat. Watch whether days 3–7 are experienced as a crash.
- **Is a balcony enough?** A child overlooking a courtyard might reach only 4 species and never hit the 10-species bonus. Possible fix: make the variety bonus relative to a personal record rather than absolute. Note that the *point values* already handle this on their own — rank-relative levels mean the balcony child's local top 10 % is worth 1,000 stars just like anyone else's (2.1). It is the **variety bonuses**, not the base points, that discriminate against a small garden.
- **How much does it actually swing?** ← **the one measurement to take before writing the scoring engine.** Run `predictAllWeeks()` once for the target region and count: how many species change level over the year, and by how many steps? How many leave the list entirely, and in which weeks? This takes an afternoon and it decides three things at once — how strong week coupling actually is under rank-relative levels (2.1), how urgent the remedies in 2.9 are, and whether `PKT-17` and `SAM-15` are telling a story worth telling. **Do not skip it.**
- **Playback abuse.** Playing bird calls from YouTube produces genuine detections. As long as there is no leaderboard there is little incentive; before any social feature this has to be solved (NFA-09).

---

## 3. Badges, Achievements and Levels

### 3.1 Two separate systems

| | **Badges** (`Auszeichnungen`) | **Achievements** (`Errungenschaften`) |
|---|---|---|
| Time frame | day or week, repeatable | permanent, one-off |
| Display | **all visible**, either earned ✓ or greyed out | **only the earned ones** |
| Purpose | "What can I still get today?" | "What have I achieved?" |
| Example | *The early bird* (still possible today) | *50 species discovered* |

**Exception:** the loyalty badges **Regular** (`Stammgast`) and **Permanent guest** (`Dauergast`) are shown **only when earned**, never greyed out. They are per species, so there would otherwise be hundreds of grey entries. What is shown per week is a list of the species it worked for.

### 3.2 Catalogue: badges (day & week)

**Daily badges** — reset every day, all always visible:

| Name | Condition | Prio |
|---|---|:---:|
| 🌅 **The early bird** (`Der frühe Vogel`) | at least 1 detection before **09:00** | P1 |
| 🌆 **Evening listener** (`Abendlauscher`) | at least 1 detection after **18:00** | P1 |
| 🎵 **Dawn chorus** (`Morgenkonzert`) | 5 different species between 05:00 and 09:00 | P1 |
| 🔟 **Ten in one go** (`Zehn auf einen Streich`) | 10 different species in one day | P0 |
| ✨ **Discovery day** (`Entdeckertag`) | at least 1 first find on this day | P1 |
| 🥇 **Rare guest** (`Seltener Gast`) | at least 1 species from the upper half of the rarity levels | P1 |
| 🌱 **Herald of spring** (`Frühlingsbote`) | a species detected that is unusually scarce here this week | P1 |
| 🗺️ **New ground** (`Neuland`) | a detection in a place never listened in before | P2 |
| 🌙 **Night owl** (`Nachtschwärmer`) | at least 1 detection after 22:00 | P2 |
| 🌧️ **Bad weather hero** (`Schlechtwetterheld`) | a detection in rain or below 5 °C | P3 |

> *The early bird* (before 09:00) and *Evening listener* (after 18:00) are deliberately easy to reach. They are not feats but **rhythm setters for the day**: once before school, once after. That is exactly the behaviour the app wants to encourage. The original *Night owl* moves to 22:00 and becomes a genuine rarity for owls and nightingales (P2) — at 18:00 the name would simply be wrong in June.

**Weekly badges** — reset on Monday, all always visible:

| Name | Condition | Prio |
|---|---|:---:|
| 📅 **Consistent** (`Regelmäßig`) | listened on at least 4 days of the week | P1 |
| 🌍 **Well travelled** (`Weitgereist`) | listened in at least 3 different places | P2 |
| 🎯 **Weekly target** (`Wochenziel`) | 5,000 stars in one week | P2 |

**Loyalty badges** — per species, only shown when earned:

| Name | Condition | Effect | Prio |
|---|---|---|:---:|
| 🤝 **Regular** (`Stammgast`) | species detected on 3 days this week | ×2 on the 3rd day | P0 |
| 🏠 **Permanent guest** (`Dauergast`) | species detected on 6 days this week | ×3 on the 6th day | P1 |

### 3.3 Catalogue: achievements (permanent)

**Collector** — number of distinct species overall:

| Tier | Species | Title |
|---|---:|---|
| 🥉 | 10 | First steps (`Erste Schritte`) |
| 🥈 | 25 | Attentive listener (`Aufmerksamer Zuhörer`) |
| 🥇 | 50 | Half a hundred (`Halbes Hundert`) |
| 💎 | 75 | Connoisseur (`Kenner`) |
| 👑 | 100 | The big hundred (`Die große Hundert`) |
| ⭐ | 150 | Species hunter (`Artenjäger`) |
| 🔥 | 200 | Ears like a lynx (`Ohren wie ein Luchs`) |
| 🏆 | 250 | Ornithologist (`Vogelkundler`) |

**Rarity** — counted at the level **at the moment of detection**:

| Condition | Title |
|---|---|
| 1 species from the upper half of the rarity levels | Lucky one (`Glückspilz`) |
| 5 such species | Tracker (`Spurenleser`) |
| 10 such species | Rarity collector (`Seltenheitensammler`) |
| 1 species at the highest level | Sensation! (`Sensation!`) |

**Year lists** *(new — the replacement for the season bonus)*:

| Condition | Title |
|---|---|
| 25 / 50 / 75 species in one calendar year | Year list I / II / III (`Jahresliste I / II / III`) |
| at least 1 detection in every month of a year | All year round (`Rund ums Jahr`) |
| 10 species first detected in spring (March–May) | The returners (`Die Heimkehrer`) |
| 5 species in December/January | Winter visitors (`Wintergäste`) |

**Family sets** *(P2 — the Pokédex effect)*: all tits, all woodpeckers, all owls, all ducks, all raptors, all thrushes, all corvids in your region, with silhouettes for the missing ones. "I only need the crested tit" is an extremely effective driver.

**Persistence:**

| Condition | Title |
|---|---|
| listened on 7 consecutive days | A week kept up (`Woche durchgehalten`) |
| listened on 30 consecutive days | A month of bird ears (`Ein Monat Vogelohren`) |
| listened on 100 days in total | A hundred days outdoors (`Hundert Tage draußen`) |
| 10,000 / 50,000 / 100,000 stars | Star collector I / II / III (`Sternensammler I / II / III`) |

> **Important:** a broken streak is **not** commented on, not marked in red and not presented as a loss. It simply starts counting again (principle 1).

### 3.4 The year list as a second collection

The year-first multiplier (M3) and the year-list achievements together form the **replacement for the removed season bonus** — and incidentally solve the app's biggest long-term problem.

The problem: after roughly 40 species the local region is largely exhausted, the life list barely grows, and motivation tips over. The year list resets on 1 January **without anything being lost** — the life list stays complete, a second count is simply added alongside it. Every spring becomes interesting again: the first blackcap of the year earns points even if you have already had it three times.

This is exactly how adult birders think ("year list", "first arrival"), it explains itself in one sentence, it cannot be gamed, and it gives the app an **annual rhythm** instead of a curve that only ever flattens.

**Presentation:** a second toggle in the collection alongside **All species** (`Alle Arten`) / **My collection** (`Meine Sammlung`): **This year** (`Dieses Jahr`) — SAM-16.

### 3.5 Levels and ranks

Levels condense the overall total into a number with a name. The curve grows by roughly a factor of 1.4 per step — fast at first for early wins, slower later for long-term motivation.

| Level | Title | From stars | Approx. with regular play |
|:---:|---|---:|---|
| 1 | Egg (`Ei`) | 0 | start |
| 2 | Chick (`Küken`) | 500 | first day |
| 3 | Nestling (`Nestling`) | 1,500 | first day |
| 4 | Fledgling (`Flügge`) | 4,000 | week 1 |
| 5 | Young bird (`Jungvogel`) | 8,000 | week 2 |
| 6 | Scout (`Späher`) | 15,000 | month 1 |
| 7 | Listener (`Lauscher`) | 25,000 | month 2 |
| 8 | Singer (`Sänger`) | 40,000 | month 3 |
| 9 | Territory holder (`Reviervogel`) | 60,000 | month 4 |
| 10 | Far flier (`Weitflieger`) | 90,000 | month 6 |
| 11 | Migrant (`Zugvogel`) | 130,000 | month 9 |
| 12 | Returner (`Rückkehrer`) | 185,000 | 1 year |
| 13 | Old bird (`Altvogel`) | 260,000 | 1.5 years |
| 14 | Flock leader (`Schwarmführer`) | 360,000 | 2 years |
| 15 | Legend (`Legende`) | 500,000 | 3 years |

*(Estimated at roughly 3,500 stars per week with regular but not daily use.)*

> **Renamed — decided.** Levels 8, 9 and 11 previously read *Kenner*, *Spurenleser* and *Vogelkundler*, which are also achievement titles (3.3). Two systems that 3.1 defines as separate cannot share names. Levels 10, 12, 13 and 14 were renamed in the same pass for a second reason: they were **human** titles (*Feldforscher*, *Artenkenner*, *Meisterlauscher*) sitting on top of a bird's life stages. **The levels now tell one story from egg to legend** — which is what `AVA-02` needs anyway, since the level *is* the avatar's stage of life. Expertise titles belong to the achievements; the levels belong to the bird.

> **Levels ratchet — decided.** The highest level ever reached is stored and never falls below it. A recomputation after a rule change (`AUS-12`, `DAT-03`) may raise a level, never lower one. Without this, the first rebalancing would take a level — and with it an avatar stage — away from a child who did nothing wrong, which principle 1 forbids. It costs one column, and it is unbuildable retroactively once children have levels.

Levels are **P1**, not P0 — the prototype only needs the raw star total. Once the avatar arrives (AVA-*), levels should unlock avatar parts.
---

## 4. Requirements Catalogue

### A · Live mode (`LIVE`)

| ID | Requirement | Prio | Acceptance criterion / note |
|---|---|:---:|---|
| LIVE-01 | Live detection with running spectrogram | ✅ | *already built, and kept at its current size.* **Decided: the spectrogram is not shrunk to make room for the scoring UI.** It is a teaching surface, not decoration — it shows how sound becomes a picture, and it makes interference visible: talk over a bird and you can watch its call disappear underneath your own voice. That is worth more than the screen area it costs. LIVE-02 to LIVE-08 are laid out **around** it |
| **LIVE-17** | **Spoken announcements stay as they are** | ✅ | *already built.* Kept unchanged, **default off**, naming the species as they do today — deliberately *not* reworded into a hint. For someone who cannot look at the screen right now, the name is the whole point, and accessibility outweighs preserving the guessing game for those who can look |
| **LIVE-18** | **Live mode says when it is not scoring** | **P0** | *New. The visible half of PKT-20.* While the detection parameters sit outside the scoring range, live mode replaces the day total (LIVE-08) with a plain, permanent notice — **"Test mode — no stars, nothing collected"** (`Testmodus — keine Sterne, nichts wird gesammelt`) plus one line saying what to change to get them back, and one saying the recordings are still kept. Requirements: **permanent**, not a toast that scrolls away; **not alarming** — no red, no exclamation mark, principle 1 says there is never a punishment; **readable by an 8-year-old**, so it names the effect ("no stars") rather than the cause ("species filter disabled"). Detections themselves keep working and are still shown, and the new-species celebration (LIVE-05/06) is suppressed — a first find that does not count must not be celebrated as if it did. Same treatment on the home screen star header, so it cannot be missed |
| LIVE-02 | Detection card shows the **stars earned** directly on the card | **P0** | Only when points are actually awarded. Format: `⭐ +100` |
| LIVE-03 | On a repeat, the card shows "already collected today ✓" (`heute schon gesammelt ✓`) instead of a number | **P0** | Prevents the question "why didn't I get anything?" |
| LIVE-04 | Card shows the applied multiplier as a chip | **P0** | e.g. `NEW ×3` (`NEU ×3`) or `REGULAR ×2` (`STAMMGAST ×2`) — never just the final number |
| LIVE-05 | A first find triggers a confetti animation | **P0** | Must not block detection; max 2 s |
| LIVE-06 | A first find shows a small species card (image, name, one sentence) | **P0** | **Non-modal**, as a bottom sheet, auto-dismissing after 6 s or on swipe |
| LIVE-07 | Simultaneous first finds are **queued** | **P0** | A walk in the woods must not stack 5 popups. Max 1 visible, the rest sequentially or as a combined "3 new species!" card |
| LIVE-08 | Running day total visible at the top of live mode | **P0** | "Today: ⭐ 850 · 9 species" (`Heute: ⭐ 850 · 9 Arten`) |
| LIVE-09 | Reaching a variety threshold is celebrated immediately | **P1** | At species 5 / 10 / 15, a short overlay with the bonus figure |
| LIVE-10 | Live mode keeps running with the screen off | **P1** | Android foreground service, iOS background audio. Without this the walking use case in 1.2 is dead. *Decided: the working implementation is **rescued** — lifted out of Survey into a standalone module before Survey is deleted, and kept compiling.* It is deliberately **not wired into Live mode for the MVP**: the prototype answers whether the game works at a window and in a garden, and screen-off operation is not needed for that. Connecting it afterwards is then a day's work rather than a rewrite |
| LIVE-11 | Notification while recording, with a stop button | **P1** | Mandatory on Android, good practice on iOS. Ships together with LIVE-10 — the rescued module already carries it |
| LIVE-12 | Confidence per detection visible, as a value or an icon | ✅ | *already built* — the live list shows a confidence bar and percentage. Remaining work is presentational only: swap the percentage for 1–3 bars, which is friendlier for an 8-year-old |
| LIVE-13 | Automatic pause after x minutes without a detection, with a prompt | **P2** | Battery protection. Default 30 min, can be turned off |
| LIVE-14 | A short audio snippet per detection, saveable and playable | **P1** | *largely built* — `DetectionClipWriter` already writes per-detection clips in Live mode, and a clip player sheet exists. **Decided: keep BirdNET Live's clip logic unchanged**; the retention policy that makes it survivable is a settings feature, SET-12. Raised from P2 because the clips are the evidence behind PKT-11 and the sample call in SAM-08 |
| LIVE-15 | "Is that right?" feedback on the card (thumbs up/down) | **P2** | Local only, a note for the user — no data transmission |
| LIVE-16 | Manually add a species seen rather than heard | **P3** | Awards 0 stars but fills the collection. ⚠️ **Must follow DAT-11:** it may *not* write to the life list, or the first-find ×3 for that species is silently burned before it is ever heard (conflict 4 in chapter 9) |

### B · Scoring (`PKT`)

| ID | Requirement | Prio | Acceptance criterion / note |
|---|---|:---:|---|
| PKT-01 | **Take the rarity level from the existing app**, for the location and the **current calendar week** | **P0** | *Decision confirmed (D3).* No separate level definition is written. The app supplies six week-accurate levels and scoring only reads them. **But read 2.1 first** — those levels are rank-relative, which is a feature (principle 3 for free) with a cost (a damped seasonal swing). Depends on DAT-10 |
| PKT-02 | Point value per level following the mapping rule in 2.3 (geometric, 50 → 1,000) | **P0** | As a configuration table, independent of the number of levels. Not scattered through the code (DAT-04) |
| PKT-03 | Points exactly **once per (day, species)** — idempotent | **P0** | Database unique constraint on `(dayKey, speciesId)`. Double awarding must be technically impossible |
| PKT-04 | First-find multiplier ×3 | **P0** | Checked against the life list, not the day list |
| PKT-05 | Loyalty multiplier ×2 on the 3rd day of the ISO week (`Stammgast`) | **P0** | |
| PKT-06 | Loyalty multiplier ×3 on the 6th day of the ISO week (`Dauergast`) | **P1** | |
| PKT-07 | **Stacking rule: only the highest multiplier counts** | **P0** | Critical for balance. Must be covered by a test |
| PKT-08 | Variety bonuses +50 / +150 (cumulative) | **P0** | From 5 and 10 species per day |
| PKT-09 | Variety bonuses +300 / +500 | **P1** | From 15 and 20 species |
| PKT-10 | Early riser bonus +50 before **09:00** | **P1** | Max 1× per day, not per species |
| PKT-11 | **Confirmation step** for detections above a point threshold | **P2** | "That would be something special! Did you see it too?" Points are awarded regardless; the species is marked *unconfirmed* until it appears a second time. *Lowered from P1: the `f_week = 0` clause is gone with the off-list case (2.3), and what remains — a misidentified species from the local rare tier — is an ordinary false positive, not a points exploit* |
| PKT-12 | **Year-first multiplier ×2** — species detected for the first time this calendar year | **P1, early** | Replaces the removed season bonus (see 3.4). Checked against the year list. **Now carries more weight than originally planned:** with the off-list case removed (2.3), the year list is the main way a child experiences the year changing. Consider pulling it into P0 — it is cheap to build and it is the seasonal signal that survives |
| PKT-13 | "New place" bonus +200 | **P2** | *Decided: the same **0.1°** grid as everything else* (gap G), not a separate 5 km one — one definition of "a different place" across the rarity scale, the place bonus and the weather cache. The place list stays local. **Cheaper than it looks by then:** the cell-change trigger from DAT-10 already fires exactly when this bonus should, so the work is a stored set of visited cells and a lookup |
| PKT-14 | Week wrap-up bonus +300 | **P2** | |
| PKT-15 | **The base point value is frozen in the `ScoreEvent`** and never recalculated | **P0** | Without this rule the history rewrites itself over the year. See 2.2 and DAT-03. **More important than originally assumed, for two reasons:** the level scale is recalibrated per *location* as well as per week (2.1), so an unfrozen base would not even be reproducible for the same child on the same day in a different park — and the confidence threshold stays user-adjustable through the MVP (gap D), so **the applied threshold must be frozen too**. Freeze at minimum: base value, level, `geoWeek`, grid cell, applied threshold, `ruleVersion` |
| PKT-16 | Every points award is **tappable and explains itself** | **P1** | "100 base × 2 (Regular) = 200" — principle 6 |
| PKT-17 | **Season hint** on the detection card when the species is currently scarcer than usual | **P1** | "🌱 Early! The barn swallow is normally only here from May — that's why it's 350 instead of 100 stars today." Still exactly right, and now doing a slightly different job: with the off-list case removed (2.3) the swings it explains are smaller, so it works less as a defence of a strange number and more as **a phenology lesson in one sentence**. Belongs with SAM-15 |
| PKT-18 | **Confidence tiering** — higher point values require higher detection confidence | **P2, not in the MVP** | *Decided: `geoExclude` stays the default (gap A), so **the confidence bar is the same for every species regardless of its point value**.* An implementation exists in the `geoAdaptive` filter mode and is documented in gap A as a future option, but it is not switched on and this requirement is not part of the MVP. Lowered to P2 because removing the off-list case (2.3) already took out the risk it was meant to cover |
| **PKT-20** | **Scoring pauses when the detection parameters leave the scoring range** | **P0** | *New. Decided.* The species filter and the confidence threshold both live in Advanced settings and both change what counts as a detection. Rather than locking them, the app **pauses the whole scoring layer** while they sit outside the scoring range — no penalty, no hidden behaviour, just a clear trade: you can experiment, but not while scoring. **Two triggers:** the species filter is off, or the confidence threshold is below the scoring minimum. **The scoring minimum is 35** — the shipped default, so the app leaves the factory sitting exactly on the floor. Restoring either resumes immediately. **The rule is deliberately asymmetric:** raising the threshold above 35 keeps scoring, because a stricter bar produces fewer and safer detections and cannot be abused; only lowering it pauses. One sentence for the settings screen: *"Higher is always allowed. Lower means no stars."* **What pauses:** stars, the collection, the life list, the year list, badges and achievements — *decided: the collection pauses too*, otherwise a lowered threshold is the shortest path to an album full of species that were never there. **What does not pause:** detection itself. The recordings are kept and shown in the journal, flagged as outside scoring (LOG-15), so nothing is lost. See SET-13 and LIVE-18 for how it is communicated, and DAT-11 for what this means in the data model |
| PKT-19 | **Damping** — point value at most 2 levels above the species' best level of the year | ~~P2~~ **probably unnecessary** | Rank-relative levels already bound how high a marginal species can climb (2.1). Kept in the catalogue only because keeping an option costs nothing; do not plan for it (2.9 c) |

### C · Badges & achievements (`AUS`)

| ID | Requirement | Prio | Acceptance criterion / note |
|---|---|:---:|---|
| AUS-01 | Badge *Ten in one go* (`Zehn auf einen Streich`) | **P0** | The one badge that is enough in the prototype to test the principle |
| AUS-02 | Loyalty badges *Regular* / *Permanent guest*, **shown only when earned** | **P0/P1** | Regular P0, Permanent guest P1. Not displayed greyed out |
| AUS-03 | Achievements "x species discovered" (10/25/50/75/100/150/200/250) | **P0** | Only the earned ones are shown |
| AUS-04 | Full daily badge catalogue (3.2) | **P1** | All visible, earned ✓ / open greyed out |
| AUS-05 | Full weekly badge catalogue (3.2) | **P1** | |
| AUS-06 | Rarity achievements | **P1** | Counted at the level **at the moment of detection**, not today's — otherwise achievements drift with the seasons |
| AUS-07 | Persistence achievements (streaks, star milestones) | **P1** | A broken streak is **not** commented on (principle 1) |
| AUS-08 | Unlock animation when an achievement is earned | **P1** | Same queuing rule as LIVE-07 |
| AUS-09 | Family sets ("all tits in your region") with silhouettes for the missing ones | **P2** | The strongest long-term driver — deliberately kept out of the prototype so it isn't burned half-finished |
| AUS-10 | Seasonal achievements | **P2** | |
| AUS-11 | Badge *Bad weather hero* (3.2 still says P3 — this row is authoritative) | **P2** | *Decided: the weather service is kept.* The inherited Open-Meteo client already has a consent gate and caches per ~10 km cell across app starts, so the badge is mostly a rule on data that is already being fetched. Raised from P3. It stays behind the same consent toggle — a child who declines weather simply never earns this badge, and nothing else changes |
| AUS-12 | Retroactive awarding when rules change | **P1** | After an update, badges already earned must be recomputable from history — see DAT-03. ⚠️ **Levels must ratchet:** store the highest level ever reached and never fall below it. A recomputation that lowers the star total would otherwise take a level and an avatar stage away from a child, which principle 1 forbids (conflict 1 in chapter 9) |
| AUS-13 | Year-list achievements (25/50/75 species per calendar year, All year round, The returners, Winter visitors) | **P1** | Together with PKT-12 this replaces the removed season bonus. Resets on 1 January without the life list losing anything |

### D · Points overview / statistics (`STAT`)

| ID | Requirement | Prio | Acceptance criterion / note |
|---|---|:---:|---|
| STAT-01 | A dedicated **Points** (`Punkte`) area, reachable from the home screen | **P0** | |
| STAT-02 | Bar chart of daily points for the last 30 days | **P0** | Days without activity shown as an empty column, not omitted — otherwise the curve lies |
| STAT-03 | Tapping a bar jumps to that day in the journal | **P1** | |
| STAT-04 | Range switch: 7 / 30 / 365 days | **P1** | |
| STAT-05 | **Tab structure** instead of a long scroll: *Overview · Badges · Achievements* (`Übersicht · Auszeichnungen · Errungenschaften`) | **P0** | Stacked vertically this gets very long on a phone. Three tabs are easy for an 8-year-old |
| STAT-06 | Key figures row: total stars, species overall, active days, longest streak | **P0** | *Decided: **a day is active when it produced at least one scoring detection**.* Not "app opened", not "session started" — a day counts when the child was outside and something was heard that counted. It is the only definition a child can check against their own journal, and it makes "active days" mean what the word says. **Detections that do not score do not count** (`PKT-20`, `LOG-15`): a day spent entirely in test mode is not an active day and does not extend a streak. That follows from the same rule rather than being an exception to it — but `SET-13` must say so, or it is a hidden consequence. Same definition for the three persistence achievements in 3.3 |
| STAT-07 | Current level with a progress bar to the next | **P1** | |
| STAT-08 | Species growth curve ("this is how your collection grew") | **P2** | Emotionally stronger than the points curve, because it only ever rises |
| STAT-09 | Personal best days ("your best day: 4,100 ⭐ on 12 May") | **P2** | |
| STAT-10 | Year in review as a shareable image | **P3** | The Spotify Wrapped principle; very effective, but only meaningful once there is data |

### E · Collection & explore (`SAM`)

| ID | Requirement | Prio | Acceptance criterion / note |
|---|---|:---:|---|
| SAM-01 | Location-based species list, sorted by frequency, detected ones ticked | ✅ | *already built* |
| SAM-02 | ~~Toggle "All species" ↔ "My collection"~~ → **The Collection (`Sammlung`) is its own area, alongside Explore (`Erkunden`)** | **P0** | *Decided: two destinations, not a toggle.* **Explore** stays what it is — every species that occurs here, whether found or not; the reference list. **The Collection** shows only what the child has actually found, and it is the thing they open in the evening. Two separate answers to two separate questions ("what could I find?" / "what do I have?"), each with its own tile on the home screen. The data layer for both already exists — a live-updating set of every species ever detected |
| SAM-03 | Every species shows a rarity badge and point value, **recognisably a weekly value** | **P0** | "What is this bird worth to me?" must be answerable before the detection. Label it "This week: 200 ⭐" (`Diese Woche: 200 ⭐`) so the change over the year doesn't read as a bug. **The value is also location-dependent** (2.1) — "here, this week" (`Hier, diese Woche`) is the honest label, and it prepares the child for the value changing on holiday (SAM-13). A rarity badge already exists in the app; only the point value is new |
| SAM-04 | **Found species show a photo, open ones a placeholder** | **P0** | *Split from the original requirement, which asked for silhouettes at P0.* The Pokédex effect rests on **the contrast**, not on the artwork: a grid where some cells carry a bird and others visibly do not is already the thing that makes a child want to fill it. The MVP gets that contrast with the placeholder image the app already ships (`dummy_species.png`) — no pipeline work, no new assets. **Decided: species images are used exactly as the original app uses them** — the bundle pipeline packs a 480×320 WebP per species, so there is no procurement project and no new licensing question |
| **SAM-04b** | **Silhouettes for undetected species** | **P1** | *Decided: not in the MVP.* Replaces SAM-04's identical placeholder with a per-species silhouette, so an open cell shows the *shape* of the bird a child is missing — recognisably a woodpecker, a duck, an owl. That is what turns a grid of blanks into a wanted list, and it is the difference between a collection that looks unfinished and one that looks designed. **Derive them from the images already in the bundle** (desaturate, flatten to a single dark tone, keep the outline) rather than commissioning drawings: one pass in the pipeline covers all ~9,800 species instead of a curated 130, and it stays correct whenever the taxonomy is rebuilt. Attribution follows the image into the derivative |
| SAM-05 | Progress indicator "37 of 128 species in your region" | **P0** | |
| SAM-06 | Species detail page: image, name, profile, where and when last heard, how often | **P1** | *partially built* — a species info overlay already shows name, description, taxonomy and external links. Missing: the personal half ("where and when **you** last heard it, how often"), which is what turns a reference page into a collection card |
| SAM-07 | Search and filters (level, family, detected/open) | ✅ | *already built* — search across the full species list, taxon-group filters, sort modes and a detected/undetected filter. Only a *family* filter is missing (needed anyway for SAM-09) |
| SAM-08 | A sample call to listen to on the detail page | **P1** | Needs licence-free recordings (check Xeno-canto, CC licences) |
| SAM-09 | Grouping by bird family with set progress | **P2** | The basis for AUS-09 |
| SAM-10 | Collectible-card view instead of a list (a card grid to flip through) | **P2** | Considerably more appealing to this audience than a list |
| SAM-11 | Child-friendly profile text per species (2–3 sentences, one mnemonic for the call) | **P1** | The app already ships offline descriptions in 11 languages — but they are written **for adults**. This is a rewrite, not a translation. Do not underestimate the editorial effort: 130 species × 3 sentences. See the locale note under SET-10 |
| SAM-12 | Mnemonics for calls ("the chiffchaff sings its own name") | **P2** | Exactly the learning effect this is all about |
| SAM-13 | Region switch / second location (holidays) | **P2** | The collection must not break when the location changes. **Cheaper than expected:** the geo model covers the whole world, so there is no region asset to swap and nothing to download — the species list simply follows the coordinates. The real work is making the *collection* honest about it: "37 of 128 at home, 12 of 190 here" |
| SAM-14 | Quiz mode: play a call, guess the species | **P3** | An obvious extension, needs its own scoring system |
| SAM-15 | **Annual cycle bar per species** — 48 weeks as a mini chart on the detail page | **P1** | **Confirmed free.** The 48-week probability curve per species is already computed and carried all the way to the UI layer — this is a chart over data that is sitting there. Makes the fluctuating points understandable ("here it's present, here it isn't") and is at the same time the best learning element in the whole app |
| SAM-16 | **A "This year" view** (`Dieses Jahr`) inside the Collection | **P1** | The year list as a second collection (3.4). Solves the motivation drop after roughly 40 species. A view within the Collection area, not a third top-level destination (SAM-02) |
| **SAM-17** | **All animal groups are collectable; the Collection filters by group** | **P0** | *New. Decided: keep every species the model knows.* Besides 8,927 birds the model already covers **340 amphibians, 268 mammals and 254 insects**, and they are active today. The Collection shows **all groups by default**, with a filter for Birds · Mammals · Amphibians · Insects (`Vögel · Säugetiere · Amphibien · Insekten`) — the same taxon filter Explore already has. A frog or a field cricket in the album is a strong draw for this age group, and the non-bird groups call in the summer months when bird activity drops. **One collection, and — decided — one shared rarity scale across all groups** (gap E): amphibians, mammals and insects take whatever rank their raw scores earn among the birds. **Two things to watch in the field test:** whether the levels (2.1) are calibrated as well for non-birds as for birds, and how much of a real collection non-birds end up making up. Run the measurement in 2.10 broken down by taxon group; per-group scales are the fallback if the groups behave very differently |

### F · Journal (previously "Sessions") (`LOG`)

> **Rename recommendation:** this area should be called **Journal** (`Tagebuch`) or **My days** (`Meine Tage`), not "Sessions". To a child a "session" means nothing; a day does.
>
> **On the accordion idea:** four nested levels (year › month › week › day) mean up to four taps on a phone before any information appears, and a constantly lost scroll position. Recommendation instead: **a flat, reverse-chronological list of day cards with sticky month headers**, plus a segmented control `Day · Week · Month · Year` at the top that switches the aggregation level. Accordions then at most **one level deep** (month → days) in the month and year views. Same information, half the taps.

| ID | Requirement | Prio | Acceptance criterion / note |
|---|---|:---:|---|
| LOG-01 | **Rebuild from recording-based to day-based** | **P0** | The core rebuild. Sessions stay in the data model but disappear from navigation. **The largest single UI job in the project** — the inherited session library and session review are ~12,000 lines built entirely around one recording, and are not salvageable as-is. What *is* salvageable from that area (export writers, clip playback, the life list) is listed in the transition document, §3.4 |
| LOG-02 | Day card shows date, day points, species count, a preview of the species | **P0** | |
| LOG-03 | Day detail: all species of that day with the **points earned per species** | **P0** | Explicitly requested; also shows the multiplier applied |
| LOG-04 | Aggregation levels day / week / month / year | **P1** | Segmented control; weeks and months show total, species count, new species |
| LOG-05 | Sticky month header while scrolling | **P1** | |
| LOG-06 | Automatic choice of starting level based on data volume | **P2** | < 60 days → day list, otherwise month view |
| LOG-07 | Expandable individual detections per species (time, spectrogram, confidence) | **P1** | This is where the old session concept lives on, one level deeper |
| LOG-08 | Calendar view with colour-coded daily intensity | **P2** | The GitHub contribution graph principle, very motivating |
| LOG-09 | New species highlighted in the day detail | **P0** | A "✨ NEW" (`✨ NEU`) marker |
| LOG-10 | A notes field per day | **P3** | |
| **LOG-13** | **The child names the place themselves** | **P1** | *New.* A recording gets a name the child types — "Oma", "Urlaub", "Schulweg", "Am Teich" — shown on the day card and in the day detail. **Editable afterwards**, so a walk can still be labelled in the evening; this is what lets a child make sense of their own recordings weeks later. Better than a geocoded place name for three reasons: it works offline, it sends nothing to anyone, and it is *their* word for the place. Reverse geocoding may fill in a suggestion where the network allows, but never overwrites what the child wrote |
| **LOG-14** | **Pick from places already used** | **P2** | A list of names the child has used before, so "Oma" is one tap rather than typed each time — and so the same place keeps the same spelling, which is what makes a per-place view possible later. Free text stays possible for a new place |
| **LOG-15** | **Detections made outside scoring still appear in the journal** | **P0** | *New. The counterweight to PKT-20 — nothing is lost, it just does not count.* Recordings made while the scoring was paused are shown in the day detail like any other, marked **"outside scoring"** (`außerhalb der Wertung`) and visibly set apart from the ones that scored. The day card counts them separately: "8 species · ⭐ 450" with "3 more outside scoring" underneath, so the day total stays honest and the recordings are still there to listen to. Wording matters: this is a *note*, not a warning — the child did nothing wrong, and principle 1 applies |
| LOG-11 | **Share a day as a single image** | **P1** | "Show grandma your bird day". *Decided: this is the only sharing path in the app.* One rendered card per day — species, stars, date — and explicitly **no audio, no coordinates, no free text** (KID-07, LOG-13). The existing HTML report is the basis. Raised from P3 because it is now the whole of sharing rather than an extra |
| LOG-12 | ~~Migrate existing session data into the day structure~~ → **Restore from backup reinstates, it does not recompute** | **P1** | *Rewritten. There are no legacy detections to migrate:* Smartfinch ships under its own application ID and installs alongside BirdNET Live, so platform sandboxing keeps the old app's session files out of reach (gap H). What remains is the restore path of `SET-07`: a backup carries the `ScoreEvent` journal, every event already holds its frozen base value, level, `geoWeek`, grid cell and threshold (`PKT-15`), and a restore therefore **writes them back unchanged**. Nothing is recomputed, so no historical lookup can go wrong. *If Phase 0 ever ships to real users before the database exists, a one-off JSON→SQLite step is needed — the cheaper answer is to keep Phase 0 internal* |

### G · Home screen (`HOME`)

| ID | Requirement | Prio | Acceptance criterion / note |
|---|---|:---:|---|
| HOME-01 | **Star header at the top**: total stars + stars over the last 30 days | **P0** | Explicitly requested. Recommendation: *total* large, *last 30 days* small next to it — the 30-day figure is the living value, the total is the pride value |
| HOME-02 | Today's figure as a third number | **P0** | "Today: ⭐ 350" (`Heute: ⭐ 350`) — the number that gets a child outside |
| HOME-03 | A **Points** (`Punkte`) button leading to the overview (STAT) | **P0** | |
| HOME-04 | **One large Live tile, plus tiles for Collection, Explore, Journal, Points and Settings** | **P0** | *Decided: the tile grid survives, its contents change.* The home screen today carries six mode tiles plus five secondary buttons; five of the six modes are being removed. What replaces them: **Live** as one large primary tile (HOME-08), then equal secondary tiles — **Sammlung**, **Erkunden**, **Tagebuch**, **Punkte**, **Einstellungen**. Collection and Explore are two separate tiles, not one (SAM-02) |
| HOME-05 | Mini sparkline of the last 7 days in the star header | **P1** | |
| HOME-06 | A "Still possible today" (`Heute noch möglich`) card with 1–2 open daily badges | **P1** | The single best lever for daily return — without a push notification |
| HOME-07 | Avatar visible on the home screen | **P1** | see AVA |
| HOME-08 | The Live mode button is visually dominant (a large primary button) | **P0** | There is exactly one thing you are meant to do: listen |
| HOME-09 | A "Recently discovered" (`Zuletzt entdeckt`) strip with the 3 newest species | **P2** | |

### H · Avatar & personalisation (`AVA`)

| ID | Requirement | Prio | Acceptance criterion / note |
|---|---|:---:|---|
| AVA-01 | An avatar figure, visible on the home screen and the points overview | **P1** | Recommendation: **your own bird as a companion**, not a human avatar — it fits the theme and is easier to illustrate |
| AVA-02 | The avatar develops with the level (egg → chick → fledgling → adult) | **P1** | Couples the level curve to something visible |
| AVA-03 | Unlockable parts: hats, binoculars, backgrounds, feather colours | **P2** | A reward for achievements, **never purchasable** |
| AVA-04 | A nest or room that fills up with achievements | **P2** | A trophy case as a place rather than a list |
| AVA-05 | A name can be chosen for the avatar | **P1** | Avoids free-text moderation issues: pick from a preset list, or keep it purely local |
| AVA-06 | The avatar comments on events ("Oh! I don't know that one yet!") | **P2** | Use sparingly, or it becomes annoying by week two |

### I · Settings (`SET`)

| ID | Requirement | Prio | Acceptance criterion / note |
|---|---|:---:|---|
| SET-01 | **Existing settings are reorganised, not cut back** | **P0** | *Decided: hide rather than delete.* There are 10 sections, 85 providers and 129 preference keys today. A plain first screen carries what a child or a parent actually touches — appearance, sounds and haptics, animation level (SET-02), location, privacy, storage, the rules page (SET-11). **Everything else moves behind "Advanced settings"** (`Erweiterte Einstellungen`), one tap away, not deleted. Nothing is lost for the adult who wants it; nothing is in the way of the child who does not. **The one genuine deletion** is the expert inference block — pooling parameters, sensitivity, custom species lists, score blacklist: those change what counts as a detection, and a settings screen that can be used to arrange your own collection has no place in a scoring app |
| SET-02 | **Animation level: Full · Reduced · Off** (`Voll · Reduziert · Aus`) | **P0** | Explicitly requested. *Reduced* = confetti only on a first find, no species card. *Off* = numbers only. Accessibility and annoyance control in one |
| SET-03 | The system "reduce motion" setting is respected | **P1** | Automatically switches to *Reduced* |
| SET-04 | Sounds and haptics separately switchable | **P1** | |
| SET-05 | Gamification fully disableable ("observation mode", `Beobachtungsmodus`) | **P2** | For accompanying adults who only want identification. **Decide before building:** whether this simply *is* PKT-20 under a friendlier name, or a separate state that also hides the star UI. One mechanism with two entry points is far cheaper than two mechanisms that both stop the scoring (conflict 12 in chapter 9) |
| SET-06 | Storage management: space used, delete audio | **P1** | Partially present via the existing data-clearing action. The missing half is the **audio expiry policy** NFA-05 asks for (default 30 days), which does not exist in any form today — while per-detection clip *writing* already does |
| SET-07 | **Backup and restore (full JSON/ZIP)** | **P1** | *Decided: this is the backup path, and it is separate from sharing (LOG-11).* Complete data, in Settings, worded for a parent — the substitute for the absent cloud backup and the only thing standing between a broken phone and a lost collection. Raised from P2: DAT-09's local backups do not survive a lost device, and this does. The research export formats (Raven, GPX) are deleted with the modes that produced them |
| SET-08 | Adjustable detection threshold | **P2** | In the Advanced area (SET-01), with a warning. Note the tension with PKT-18: lowering the threshold raises the number of expensive misdetections, so a changed threshold should be recorded in the `ScoreEvent` |
| **SET-12** | **Audio clip retention: how long, how many, in what order** | **P1** | *New. Decided.* Clips are written as BirdNET Live writes them; what is new is the clean-up. **Deletion order:** the most-recorded species first, and within a species the lowest confidence first — so the hundredth mediocre blackbird goes before the only nuthatch. **Two thresholds, both adjustable:** delete only once a clip is older than **30 days**, and only above **100 clips per species**. **Favourites are never deleted** — a child marks the recordings they want to keep, and the app shows how many of the cap they have used. This makes LIVE-14 compatible with NFA-05 instead of exempt from it. *Set the defaults generously and check them against the field test; nobody has yet measured what a child actually accumulates in a month* |
| **SET-13** | **Warning on the settings that stop scoring** | **P0** | *New. The settings half of PKT-20.* The species-filter switch and the confidence slider both carry a warning **at the moment of change**, not buried in a help text: turning the filter off, or dragging the threshold below the scoring minimum, shows what it costs — *"While this is switched off there are no stars, nothing is added to the collection, and the day does not count towards your streak. Detection keeps working, the recordings are kept, and everything already collected stays."* Every part matters: the honest trade, **the streak consequence** — which follows from `STAT-06`'s definition and would otherwise be a hidden effect discovered days later — the reassurance that recordings are not thrown away, and the reassurance that existing progress is untouched. **Requires a confirmation step**, because it is reachable by an adult experimenting on a child's device. The slider should show the scoring floor (35) as a marked point on its track, so it is visible *before* the drag rather than only in the warning afterwards. The floor itself is a constant, not a setting |
| SET-09 | **Set the home region — as part of onboarding** | **P0** | *Raised from P2. Decided: without a position there is no rarity level and therefore no stars (gap F), so the region cannot be optional.* The mechanism is already built — a GPS on/off switch with manual coordinates, enforced inside the location service so every feature honours it. What is new: it happens at first run, it must work for a child who declines GPS (pick on a map or by place name, not a latitude field), and it shares a screen with the permissions rather than adding a fifth one (KID-01). Wording matters here — this is where a parent decides whether to trust the app with location, so it belongs beside the KID-08 notice |
| SET-10 | Language German / English | ✅ | *already built, and then some* — the app ships **12 UI locales** (en, de, cs, es, fr, it, pt, nl, nb, pl, ru, zh) and offline species descriptions in 11. **Decision: keep all 12.** The consequence is a standing obligation — every new Smartfinch string needs 12 translations from day one, per the project's own l10n rules. **Recommendation:** hold that line for *UI strings only*. The child-register species profiles (SAM-11) should ship German first, English second, with the other ten keeping the adult descriptions until someone funds the rewrite |
| SET-11 | Scoring rules readable in-app ("How do I earn stars?", `Wie bekomme ich Sterne?`) | **P0** | Principle 6. An illustrated page in child-friendly language — with its own section **"Why do the points change during the year?"** (`Warum ändern sich die Punkte im Jahr?`), or week coupling looks like a bug |

### J · Child-appropriateness & onboarding (`KID`)

| ID | Requirement | Prio | Acceptance criterion / note |
|---|---|:---:|---|
| KID-01 | Onboarding in at most 4 screens, no account | **P0** | Microphone and location permissions explained before the system asks. **The four screens now also have to carry the home region** (SET-09, gap F) — it shares the permissions screen rather than adding a fifth. The budget is tight; the first guided detection (KID-02) is the pressure valve, since it can happen *after* onboarding rather than inside it |
| KID-02 | A first guided detection as part of onboarding | **P1** | "Go to the window and press start" — the first first-find has to happen within the first 5 minutes |
| KID-03 | Language and font size suitable for an 8-year-old | **P0** | Short sentences, no unexplained jargon, minimum 16 sp base size |
| KID-04 | All core functions operable without reading (icons + colour) | **P1** | |
| KID-05 | No time pressure elements, no countdowns | **P0** | Principle 1 |
| KID-06 | No push notifications with pressuring wording | **P1** | If push at all: at most 1×/day, friendly, switchable, **off** by default |
| KID-07 | No free text that could reach another person | **P0** | Trivial while offline. **One exception now exists and must be handled deliberately:** the place names in LOG-13 are free text a child types. They stay local, and the shared day image (LOG-11) is rendered **without them** — a place name is for the child's own memory, not for anyone else's screen. Re-examine before any social feature |
| KID-08 | A parent notice at first start (privacy, microphone, what happens to the data) | **P1** | Once, understandable, retrievable again from settings |
| KID-09 | Safety note "don't go to unfamiliar places alone" alongside place bonuses | **P2** | As soon as PKT-13 arrives |
| KID-10 | Screen time limits set by parents | **P3** | Honestly: the app is meant to lead outside, not to the screen |

---

## 5. Non-Functional Requirements (`NFA`)

| ID | Requirement | Prio | Target / note |
|---|---|:---:|---|
| NFA-01 | **Fully operable offline** | **P0** *(met for every core function)* | No **core** function may require a network — and none does: inference, geo model, rarity levels, scoring, collection, journal and species descriptions are all local assets. *Decided: maps and weather are kept*, so the `INTERNET` permission stays. Both are **accessories, not core**: each sits behind its own consent toggle, each degrades to "not available right now" without breaking anything, and the app stays fully playable in a dead zone in the woods. The one thing to hold the line on: **nothing that awards a star may ever depend on the network** |
| NFA-02 | Cold start to live detection | **P0** | < 3 s from tapping the icon to a running spectrogram |
| NFA-03 | Battery drain in continuous operation | **P1** | ≤ 12 % per hour on mid-range devices; verifiable with a test protocol |
| NFA-04 | Thermal behaviour | **P1** | No device heat warning after 60 min of continuous operation; automatically stretch the inference interval under throttling |
| NFA-05 | Storage budget | **P1** | App + assets ≤ 250 MB; user data grows ≤ 5 MB/month without audio. Audio has an expiry (default 30 days). ⚠️ **Already tight:** the shipped models are 91 MB (67 MB classifier + 14 MB geo model + 13 MB taxonomy) before a single species photograph is added. ~130 photographs plus silhouettes will consume much of the remaining headroom. The existing Play Asset Delivery setup is what makes this survivable — keep it |
| NFA-06 | Scoring is **deterministic and reproducible** | **P0** | The same detection history always yields the same total. Unit tests mandatory |
| NFA-07 | Privacy: no personal data leaves the device | **P0** *(close to met)* | No analytics SDK, no crash reporter carrying location data, no advertising IDs. GDPR Art. 8 (children) and the Google Play Families policy apply. The inherited app already carries no analytics and no ad IDs — a genuinely good starting position. What remains is the outbound traffic listed under NFA-01 (map tiles, reverse geocoding, weather), each of which sends a location to a third party |
| NFA-08 | Location used locally and **coarsened** only | **P0** | *Decided: the grid is **0.1°*** — 11.1 km of latitude, ~7 km of longitude here (gap G). Never store precise coordinates. Going further than the letter of this requirement: *decided,* **`LocationAccuracy.high` is dropped** — the app requests roughly the 1 km class instead of ~10 m, so it never holds a precision it has no use for. **GPS itself stays**; this is about what is asked for, not about the source. ⚠️ **Not met today, in two ways.** The app currently stores precise GPS tracks (survey mode) and declares `ACCESS_FINE_LOCATION` **and** `ACCESS_BACKGROUND_LOCATION`. Removing the research modes removes the track storage; dropping the background-location permission should happen in the same pass. It is a Play Store review flag, and for a children's app it is one you do not want to have to justify. **Second reason coarsening is now mandatory:** because levels are rank-relative (2.1), an uncoarsened location re-ranks the species list as the child walks, and the same bird changes value mid-session |
| NFA-09 | A fair-play concept before any comparison feature | **P2** | Playback detection is barely solvable technically. With no leaderboard there is no incentive — which is why social is deliberately P3 |
| NFA-10 | Accessibility | **P1** | AA contrast, text scaling to 200 %, screen reader labels, "reduce motion" (SET-03) |
| NFA-11 | Data safety on crash | **P1** | Detections are persisted immediately, not when the session ends. ⚠️ **The opposite is true today** — a session is written to disk as one JSON file when it ends, so a crash loses the whole session. Fixed by DAT-01 rather than separately |
| NFA-12 | Migration of existing data on every schema update | **P0** | Tested upgrade and downgrade paths. A child who has collected 200 species loses nothing on an update |
| NFA-13 | Flutter-specific: inference in an isolate, UI stays at 60 fps | ✅ | *already built exactly as specified* — inference runs in a dedicated isolate and the spectrogram is a `CustomPainter` on its own layer. Do not restructure this code; it is also where upstream fixes land (see the merge note in the transition document) |
| NFA-14 | Test coverage of the scoring engine | **P0** | The rules from chapter 2 as a test table; every rule change needs a test |

---

## 6. Data Model & Architecture Decisions (`DAT`)

### 6.1 The one decision everything rests on

| ID | Requirement | Prio |
|---|---|:---:|
| **DAT-03** | **Points are stored as an immutable event journal (`ScoreEvent`), never as a bare counter. Every entry carries a `ruleVersion` and the **frozen base point value**. The full score can be recomputed from the `Detection` records at any time (`recomputeAllScores()`) — where the recomputation re-derives multipliers and bonuses but never touches the stored base value.** | **P0** |

Why this is the most important sentence in the document: the balancing in chapter 2 will change. After four weeks of real use it will turn out that the variety bonus kicks in too early or the loyalty multiplier is too strong. If the score is only a number in a row, a rule change is either impossible or it destroys progress. With a journal and a recomputation it is a button press — including retroactively correct badges (AUS-12) and the migration of legacy data (LOG-12).

**The split is mandatory because of week coupling.** A detection's base value depends on how rare the species was *in that exact calendar week*. If a recomputation re-derived it, a child's May outing would suddenly be worth more in December and their points history would no longer match what they actually saw. Hence: **base = snapshot, rules = recomputable.** This holds even if the range data (DAT-06) is later replaced with a newer version.

### 6.2 Entities (sketch)

```
Species          id, sciName, deName, family, imageRef, profile
                 // NO fixed level — that comes per week from SpeciesRange
SpeciesRange     speciesId, gridCell, week(1..48), frequency, level
                 // BirdNET range model; level = rarity level of the existing app
                 // f_year = max(frequency over all weeks) — only for SAM-15 and PKT-19

Session          id, startedAt, endedAt, gridCell
Detection        id, sessionId, speciesId, timestamp, confidence,
                 spectrogramRef, audioRef?          // raw data, never modified

DaySpecies       dayKey, speciesId, firstDetectionId, count, awardedPoints,
                 confirmed                          // PKT-11
                 UNIQUE(dayKey, speciesId)          // enforces PKT-03

ScoreEvent       id, dayKey, timestamp, type, speciesId?,
                 levelAtDetection, base,            // FROZEN (PKT-15)
                 multiplier, bonus, total, ruleVersion
                 // append-only; type ∈ {SPECIES, VARIETY, EARLY, PLACE, WEEK}

DayScore         dayKey, total, speciesCount        // materialised, for the chart only
YearSpecies      year, speciesId, firstDetectionId  // year list for PKT-12 / SAM-16
                 UNIQUE(year, speciesId)
Achievement      key, type, tier, unlockedAt, progress
UserProfile      totalStars, level, avatarState, homeCell
```

### 6.3 Further architecture requirements

| ID | Requirement | Prio | Note |
|---|---|:---:|---|
| DAT-01 | A local relational database with migrations | **P0** | For Flutter: Drift (SQLite, type-safe, good migrations) or Isar. Drift is the safer choice for this query shape. ⚠️ **This is the single largest technical gap.** There is no database of any kind today — persistence is one JSON file per session plus 129 preference keys, with no schema, no migrations, no queries and no constraints. `PKT-03`'s "double awarding must be technically impossible" is a `UNIQUE` constraint, and there is currently nothing to put it on. Introduce the database **before** any scoring UI is written |
| DAT-02 | `Detection` is the single source of truth; everything else is derivable | **P0** | |
| DAT-04 | Scoring rules as a **configuration object**, not constants scattered through the code | **P0** | A `ScoringRules` object with a version; allows balancing changes without a code rewrite |
| DAT-05 | `dayKey` as the local calendar day (`YYYY-MM-DD`), `weekKey` as the ISO week | **P0** | Test timezone and daylight-saving transitions explicitly |
| DAT-06 | ~~Ship range data at weekly resolution as a precomputed asset~~ → **Use the bundled geo model as the range-data source** | ✅ | *Solved by the existing app, and better than specified.* A 13.6 MB ONNX model takes `[latitude, longitude, week]` and returns a per-species probability for **any of 48 weeks anywhere on Earth**. No precomputed table, no region cropping, no reload on region change — which also makes SAM-13 (holidays, second region) and SET-09 (manual home region) nearly free. **What remains to be built** is caching: see DAT-10 |
| DAT-07 | The schema keeps multi-user open (`profileId` from the start) | **P1** | Costs almost nothing today and is the prerequisite for family profiles and the teacher mode |
| DAT-08 | The schema keeps sync open (`updatedAt`, `syncState`, stable UUIDs) | **P2** | Only provide the fields, don't build sync logic — see IDEE-01 |
| DAT-09 | Automatic local backup (rolling, 3 generations) | **P1** | Protects against the worst imaginable failure: a lost collection |
| **DAT-11** | **A detection carries whether it was in scoring; the scoring layer is simply not written for the ones that were not** | **P0** | *New. The data-model half of PKT-20, and the place it is easiest to get wrong.* The split is clean and follows DAT-02: a paused detection is still written to `Detection` — with a flag recording that scoring was paused and why — but **no `ScoreEvent`, no `DaySpecies`, no `YearSpecies` row is created, and the life list is not touched.** Three consequences, each of which is a bug if missed: **(1)** the life list must not learn the species, or the first-find ×3 (PKT-04) is silently burned — a child who "found" a nuthatch in test mode would never again get the first-find bonus for their real one, which is exactly the hidden punishment principle 1 forbids; **(2)** the same species can therefore score normally later that same day, because no `DaySpecies` row blocks it (PKT-03); **(3)** `recomputeAllScores()` (DAT-03) **must respect the flag** — a recomputation that ignores it would retroactively award every test recording ever made |
| **DAT-10** | **One shared, cached rarity-level scale for the whole app** | **P0** | *New, and a direct consequence of 2.1.* The level scale is currently built inside the Explore screen's own provider, from 48 model inferences, scoped to that screen. Scoring needs the identical scale at detection time in Live mode. Extract it into a **shared provider keyed by `(gridCell, geoWeek)`**, where the cell is the 0.1° cell of gap G. If Explore and Live can disagree about what a bird is worth, principle 6 breaks loudly and in front of the child. **Rebuild rule:** the position is re-checked roughly every 5 minutes at *coarse* accuracy, and the scale is rebuilt **only when the cell changes** — so the 48 inferences run almost never. Three constraints on the rebuild: it runs **in an isolate** (a live session must hold 60 fps, `NFA-13` — the existing Explore code runs these on the main isolate because there it happens once on a loading screen); the **current scale stays in use until the new one is ready**, because nothing may interrupt listening (principle 7); and a **small LRU cache** of recent `(cell, geoWeek)` scales keeps a route that crosses a boundary from rebuilding back and forth |

---

## 7. Release Plan

### P-1 — Clearing the ground (before any Smartfinch feature)

*Added after the codebase review. Not a product phase — a precondition.*

Smartfinch is a fork of BirdNET Live, and roughly a quarter of the inherited feature code belongs to research tooling that has no place in a children's app. Removing it first means every later change is made in a smaller, comprehensible app.

1. **Rebrand the identifiers** — package name, application IDs, icons, store metadata. Use a *new* application ID so Smartfinch installs alongside BirdNET Live rather than replacing it. Keep the BirdNET model licence and attribution visible; those obligations do not go away.
2. **Delete Survey, ARU, Point Count, File Analysis and Batch Analysis** (~20,000 lines). They are cleanly decoupled — only three files in the whole codebase import them.
3. ⚠️ **Rescue background recording first.** The only working foreground-service implementation lives inside the modules being deleted (see LIVE-10). Port it to Live mode *before* deleting them, or it has to be rewritten later.
4. **Prune the settings screen and the ARB files** (SET-01), and drop the now-unnecessary `ACCESS_BACKGROUND_LOCATION` permission (NFA-08).
5. Ship it internally. If something is broken, you know it was the deletion — not the scoring engine you have not written yet.

The full inventory, with a keep/change/remove verdict per module and an upstream-merge strategy, is in **`BirdNET_Live_to_Smartfinch_Transition.md`**.

### P0 — Prototype: "Does the game mechanic work?"

**Goal:** a child keeps playing voluntarily for two weeks. Everything else is secondary.

The prototype builds on what exists and adds exactly four things:

0. **The foundation under the engine** — DAT-01 (introduce the database at all) and **DAT-10** (the shared cached level scale). None of this is visible to a child, and none of it can be retrofitted later. *Build the database before Phase 0 reaches any real user, and there is no migration to write at all (LOG-12)*
1. **The scoring engine** — PKT-01 to PKT-08, **PKT-15**, DAT-02 to DAT-05, NFA-06, NFA-14. **Pure Dart, no UI.** It is finished when the chapter 2 rule table passes as a test suite, and not before
2. **Making points visible** — HOME-01/02/03/08, LIVE-02 to LIVE-08, LOG-03, SET-11
3. **The journal instead of sessions** — LOG-01/02/09/12
4. **The collection** — SAM-02 to SAM-05 (photo vs. placeholder; the per-species silhouettes of SAM-04b are P1), SAM-17, AUS-01/02/03, STAT-01/02/05/06

Plus the foundations that cannot be retrofitted: NFA-01, NFA-07, NFA-08, NFA-12, KID-01, KID-03, KID-05, KID-07, SET-02. Include `profileId` (DAT-07) and the sync fields (DAT-08) in the very first schema — they cost a few columns now and are effectively unbuildable later.

> **One measurement before step 1:** run the annual-swing check from 2.10. It takes an afternoon and it tells you how much of chapter 2's seasonal story is actually there to tell.

**Deliberately left out:** levels, avatar, background operation, species detail pages, the full badge catalogue. All of those can follow later — but if week two shows nobody opens the app, they would have been built for nothing.

**What to measure over those two weeks:** on how many days was the app opened? How many species accumulated? Did the child go somewhere once that they would not otherwise have gone? The last question is the real one.

### P1 — Version 1.0: publishable

The full badge and achievement catalogue (AUS-04 to AUS-08, AUS-12, AUS-13), **the year list as a second collection** (PKT-12, SAM-16), **making week coupling visible** (PKT-17, SAM-15), **the countermeasures against misdetections** (PKT-11, PKT-18), levels and avatar (STAT-07, AVA-01/02/05, HOME-07), background operation (LIVE-10/11), species detail pages with profile and sample call (SAM-06/07/08/11), **the silhouettes** (SAM-04b — the collection stops looking unfinished), the range switch in the journal (LOG-04/05/07), "Still possible today" (HOME-06), accessibility (NFA-10), backup (DAT-09), the parent notice (KID-08).

> **Ordering note:** PKT-17 and SAM-15 belong together and should come early in P1. As long as points fluctuate over the year without the app explaining why, week coupling reads as a bug — with the explanation it becomes the strongest learning element in the product.

### P2 — Version 1.x: depth

Family sets and collectible cards (AUS-09, SAM-09/10) — the strongest long-term driver. Seasonal achievements (AUS-10). Place bonuses (PKT-13, KID-09). Damping in reserve (PKT-19). Calendar view and species curve (LOG-08, STAT-08). Data export (SET-07). Observation mode for adults (SET-05). Call mnemonics (SAM-12). Second region (SAM-13, SET-09).

### P3 — Vision

Everything in chapter 8. The only thing to do today is to **include DAT-07 and DAT-08 in the schema.** That costs a few columns and keeps the door open.

---

## 8. Further Ideas (`IDEE`)

These are deliberately not part of the roadmap — they are directions to keep open.

### 8.1 Account & sync (`IDEE-01`)

The trigger will be a lost or replaced phone. Until then, data export (SET-07) is the honest interim solution. If sync arrives it should be an **optional add-on**, never a prerequisite: the app must still work fully without an account afterwards. The schema prerequisite is DAT-08.

### 8.2 Friends and leaderboards (`IDEE-02`)

The most obvious extension and simultaneously the most delicate one.

**What would work:**

- **Small closed groups** instead of global leaderboards — family, school class, club. A worldwide ranking would demotivate an inner-city child, because home and habitat determine the outcome more than effort does.
- **Cooperative rather than competitive:** "together we found 62 species" is more motivating for this age group, and socially healthier, than "you are fifth".
- **Weekly group challenges:** "find five woodpeckers between you."
- Join by **invite code with no search function** — you cannot find other people's children.

**What must be solved first:** the playback problem (NFA-09), because a leaderboard creates a genuine incentive to cheat; a child protection concept with no free text (KID-07); and an account (IDEE-01). Which is why this is honestly P3 and not P2.

### 8.3 Teacher and group mode (`IDEE-03`)

For school classes, forest kindergartens and youth nature groups — substantively the strongest idea in this document, because it takes the app out of the bedroom and into a context where adults guide the learning.

Conceivable: a class code, a shared species list ("our schoolyard"), a project week as a time frame, a printout of the class collection for the classroom, prepared excursion tasks ("find three species that live near water"). The prerequisites are DAT-07 (profiles) and an adult area that is deliberately *not* a surveillance feature but a group overview.

A realistic entry point would be a partnership with an existing initiative — Germany's **NABU garden bird counts (`Stunde der Gartenvögel` in May, `Stunde der Wintervögel` in January)** hit exactly this audience and occasion, and a time-limited in-app event around them would be a natural fit.

### 8.4 Other directions

| ID | Idea | Comment |
|---|---|---|
| IDEE-04 | **Map & heatmap** of your own finds | Emotionally strong ("my territory"), delicate on privacy — local only, never shareable |
| IDEE-05 | **Call quiz** as a separate game mode | The most direct learning effect. Needs its own separate scoring |
| IDEE-06 | **Other animal groups** — frogs, bats, grasshoppers, crickets | Neighbouring BirdNET-style models partly exist; would open the app from birds to nature generally |
| IDEE-07 | **Citizen science**: submission to ornitho.de / eBird | Only with adult approval and a quality check — false records from a child's phone damage real databases |
| IDEE-08 | **A printable paper collection album** | Turns screen time into craft time; a perfect fit for this audience |
| IDEE-09 | **A home screen widget** with today's total | The cheapest return mechanism there is |
| IDEE-10 | **Seasonal events** around the NABU counts | Time-limited, with their own badge |
| IDEE-11 | **Sibling / family profiles** on one device | Requires DAT-07; simpler than real social and almost as effective |
| IDEE-12 | **Year in review** as a shareable image | One image per year, no account needed |

---

## 9. Risks and Open Questions

| Risk | Impact | Handling |
|---|---|---|
| **Balancing is wrong** — too generous or too stingy | The core risk of the whole concept | DAT-03/DAT-04: rules are versioned and retroactively recomputable. Balancing is a setting, not a rebuild |
| ~~Misdetections become the best points source~~ | Was the central risk of week coupling | **Designed out.** Two decisions did it: levels are a bounded rank rather than an inverse frequency (2.1), and a species with no local level scores nothing (2.3). What remains is an ordinary false positive from the local rare tier, capped at 1,000 stars — the same error rate the app already lives with. PKT-11 and PKT-18 drop to P2, PKT-19 is not needed. Detail in 2.9 |
| **The seasonal signal is now thin** | Removing the off-list case (2.3) leaves rank shift as the only seasonality inside the point value, and rank shift is the damped mechanism. A child may not notice that the year outside changes at all — which was one of the two things the app was for | **The year list has to carry it**: year-first multiplier (PKT-12), "This year" view (SAM-16), year achievements (AUS-13). All three move to *early* P1, and PKT-12 is worth pulling into P0. The annual cycle bar (SAM-15) and season hint (PKT-17) teach phenology directly and become more important, not less |
| **Misdetections generally** | A child collects species that were not there; trust erodes | Show confidence (LIVE-12), never sell detections as facts, mark as "unconfirmed" (PKT-11) |
| **Fluctuating points look arbitrary** | A child doesn't understand why the same blackbird is worth more in winter; trust in the numbers erodes (principle 6) | PKT-17, SAM-15, SAM-03 and the explanation section in SET-11 are not optional polish — they are the precondition for week coupling working at all |
| **An inner-city child makes no progress** | The audience is partly excluded | **Mostly solved for free.** Because levels are relative to the child's own local list (2.1), a balcony child's rarest tenth is worth 1,000 stars just like anyone else's. The residual risk sits in the *variety bonuses*, which are absolute — a courtyard with four species never reaches the 10-species step. Watch that specifically; the fix is a bonus relative to a personal record (2.10) |
| **Battery in continuous operation** | The walking use case dies, parents uninstall | NFA-03/04 as hard targets with a measurement protocol; automatic pause (LIVE-13) |
| **Editorial effort for species texts underestimated** | v1.0 slips | SAM-11 is P1, not P0. 130 species × text + image + licence is weeks of work — start early, in parallel with development |
| **Image rights and call recordings** | A legal problem at publication | Use only CC-licensed sources (Xeno-canto for calls, Wikimedia Commons for images), document licences, attribute in-app |
| **Motivation drop after ~40 species** | The local common species are done by then | The first safety net is the **year list** (PKT-12, SAM-16, AUS-13) — it resets every January without anything being lost and makes every spring interesting again. After that, family sets (AUS-09) and place bonuses (PKT-13). Both should be ready before the drop happens |
| **Playback cheating** | Destroys any comparison feature | Social stays P3 until NFA-09 is solved |
| **The seasonal swing turns out to be small** | Chapter 2's central idea is week coupling. If rank-relative levels damp it to near-nothing in the target region, PKT-17 and SAM-15 explain a phenomenon the child never notices — and chapter 2's argument thins out | The measurement in 2.10 tells you this **before** you build the UI for it. If the swing is small, the off-list case (2.2) and the year list (PKT-12, SAM-16, AUS-13) carry the seasonal story instead |
| **A schema update loses a collection** | The worst possible failure. A child who has collected 200 species and loses them will not come back | `NFA-12` with tested upgrade *and* downgrade paths on every schema change, plus `DAT-09`'s rolling local backups. Note this is now purely about *future* Smartfinch schema changes — there are no legacy data to migrate in the first place (gap H), so the risk starts smaller than assumed |
| **A lost phone loses a collection** | More likely than a bad migration, and completely unrecoverable without a cloud | `SET-07` (backup/restore, raised to P1) is the only defence, and it only works if a parent actually runs it. Worth a gentle reminder in the app after the first 50 species — the point where the collection starts being worth something to the child |
| **The fork drifts from upstream** | BirdNET model updates, ONNX runtime fixes and platform fixes stop arriving. Over a year this quietly becomes a hard fork nobody chose | Keep inference, audio, recording and spectrogram structurally close to upstream; put all Smartfinch code in new directories; merge monthly. Strategy in the transition document, §7 |

**Open questions to settle before the prototype:**

1. ~~**How many rarity levels does the existing app have**, and are they already week-accurate?~~ **Answered by the codebase review.** **Six** levels, week-accurate across all 48 weeks, worldwide — but **rank-relative rather than absolute**, which changes how week coupling behaves. See 2.1 and 2.2. DAT-06 turns out to be already done; DAT-10 is the work that replaces it.
2. **How much does it actually swing in the target region?** Still open, and now the **single most valuable measurement in the project** — see 2.10. An afternoon's work; do it before writing the scoring engine.
3. Is the star header on the home screen built with **30 days or 7 days** as the second figure? Recommendation: 30 days, large enough to carry over a bad week.
4. Are **audio snippets** stored from the start? This significantly affects the storage budget and the privacy notice. Recommendation: not in the prototype. *Note: the machinery already exists and is already wired into Live mode — so the decision is whether to switch it off, not whether to build it. What genuinely does not exist is the expiry policy (SET-06, NFA-05).*
5. Does the **year-first multiplier** (PKT-12) go into the prototype already? It is cheap to build and would make week coupling tangible from day one — but it currently sits at P1. *Given that rank-relative levels damp the seasonal swing (2.2), the argument for pulling it into P0 is now stronger: it may be the clearest seasonal signal a child actually notices in the first two weeks.*

### Specification gaps that block the MVP — and how they were settled

*Added after a third pass, this time reading the detection pipeline rather than the feature list. These are not product questions — they are places where the scoring engine could not be written until someone decided.*

**All eight are now settled.** Seven by decision, one (**H**) withdrawn because the case it described cannot occur. The scoring engine can be specified end to end from here.

**A. The off-list case versus the default filter — ✅ settled, by changing the rule instead of the filter**

The conflict was: 2.3 gave a species that is not on this week's local list the top level and full points, while the app's default filter **`geoExclude`** drops every species below the geo threshold (0.03) *before it reaches the detection list*. The 1,000-star case could not occur.

> **Decided: `geoExclude` stays the default, and the off-list rule is removed instead** (2.3). A species with no local rarity level scores nothing. Rule and filter now say the same thing, which is why this is the cleaner of the two fixes — the alternative would have kept a rule the default configuration contradicts.

**What follows:**

- The main risk in 2.9 is designed out rather than defended against. `PKT-11` and `PKT-18` both drop to P2.
- The seasonal story moves to the year list — `PKT-12`, `SAM-16`, `AUS-13`. See 2.2.
- **Write the rule against the *level*, not the filter:** "no rarity level, no stars". Then it stays correct whatever the filter mode is, including `off`.
- **The filter mode belongs in Advanced settings** (`SET-01`), and **switching it off stops scoring entirely** (`PKT-20`) — not merely for the unlevelled species it lets through. Otherwise `off` would fill the list with implausible species while scoring continued around them, and the app's honesty suffers. The warning and the live indicator are `SET-13` and `LIVE-18`.

**`geoAdaptive` is kept as a documented future option**, not deleted. It implements `PKT-18`: the required audio confidence rises with how unlikely the species is at this location, on the same `ExploreTierScale` the scoring engine uses, calibrated across 20 locations × 4 seasons. **None of this is active in the MVP** — under `geoExclude` every species faces the same confidence bar:

| Tier at this location | Confidence roughly required |
|---|---|
| Abundant | any score above the threshold |
| Common | ~0.55–0.70 |
| Frequent | ~0.70–0.82 |
| Uncommon | ~0.78–0.89 |
| Scarce / Rare | ~0.83–0.92 |
| Not on the local list | ~0.92–0.97 |

**When it would be worth switching on:** if the field test shows false positives from the local rare tier becoming a points source, `geoAdaptive` raises the bar for exactly those species without touching anything else. It is a one-line default change, so there is no reason to build it into the MVP — only a reason to keep it documented and reachable.

**B. "Week" means two different things — a naming rule, not a decision**

`GeoModel.dateTimeToWeek()` returns **4 weeks per calendar month** (1–48; the fourth week of a month runs 9–10 days). `DAT-05` and the loyalty multipliers `PKT-05`/`PKT-06` mean the **ISO week**, Monday to Sunday. These are different calendars and they must never be confused:

- `geoWeek` (1–48) — looks up the rarity level. Belongs to the frozen base value (`PKT-15`).
- `isoWeek` — counts loyalty days, drives `PKT-05`, `PKT-06` and the week wrap-up `B8`.

Both go into the `ScoreEvent` under distinct names. Getting this wrong produces a bug nobody will find for months.

**C. What exactly is one scoreable detection? — ✅ settled**

The pipeline does not emit discrete detections. `DetectionAccumulator` keeps a species *active* across inference windows, updates its peak confidence, and closes the record when it drops out.

> **Decided: a detection scores the moment it is shown.** The first inference window that clears the threshold creates the `ScoreEvent` — so the stars appear at the same instant the species does (`LIVE-02`), which is the whole point of the seconds-level reward rhythm in 1.3. **The peak confidence is written back when the record closes**, so `PKT-11` and any later audit see the best evidence rather than the first frame.

Two implementation consequences: the `ScoreEvent` is written once and updated once, so its confidence field must be nullable-then-filled rather than final on insert; and a species that flickers in and out produces one event per *record*, not per window — `PKT-03`'s `UNIQUE(dayKey, speciesId)` makes the second appearance award nothing anyway.

**D. Which confidence threshold governs the points? — ✅ settled, with a caveat**

The user-adjustable threshold defaults to **35** (i.e. 0.35) and lives in Settings.

> **Decided: the existing slider governs the points, moved into Advanced settings (`SET-01`), and kept adjustable through the MVP as a test instrument** — the prototype is precisely where you want to try different thresholds against a real child and real birds.

> ⚠️ **This makes `PKT-15` load-bearing in a new way.** The applied threshold **must** be frozen into every `ScoreEvent`. Without that, moving the slider silently rewrites the meaning of the whole history, and `NFA-06` (deterministic, reproducible scoring) fails.

**And it is what `PKT-20` solves.** The objection to a shippable slider was that a control in the settings screen can change the scoring rules. The answer is not to lock it but to bound it: **below a fixed scoring minimum the app simply stops awarding points**, says so where it is changed (`SET-13`) and says so in live mode (`LIVE-18`). An adult can still experiment, a child can still see what the app hears — the scoring just steps aside while the parameters are outside its range. No penalty, no hidden behaviour, and no need to revisit this after the field test.

**The scoring minimum is settled: 35** — the shipped default becomes the floor. Everything at or above the default scores; below it, `PKT-20` pauses. It is a constant in the scoring rules (`DAT-04`), not a setting, and it means the app ships sitting exactly on its own floor: a child who never opens Advanced settings is always scoring, and the only way out of the scoring range is a deliberate downward drag past a warning.

`PKT-15` still has to freeze the applied threshold, because the range above 35 stays adjustable and a stricter setting produces fewer detections — the history has to record which bar applied.

**E. One rarity scale for all animals, or one per group? — ✅ settled**

> **Decided: one shared scale for all animals.** Simpler, cheaper, and consistent with `SAM-17`'s single collection — one album, one scale. Amphibians, mammals and insects take whatever rank their raw scores earn among the birds.

**This is the assumption in the whole design most likely to need revisiting**, and it is worth watching deliberately in the field test. Two ways it can go wrong in opposite directions: a chorus of common frogs may score high enough to sit in the abundant tier and be worth almost nothing, or the geo model may be poorly calibrated for insects and push genuinely common species into the rare tier, where they pay 1,000 stars. Run the measurement in 2.10 **broken down by taxon group** — if the groups behave very differently, per-group scales are the fallback.

**F. No location means no points — ✅ settled**

The rarity level requires a position. A child who declines the location permission, or is indoors without a fix, generates detections with no level and therefore no stars — on first launch, which is exactly when the game has to work.

> **Decided: the home region is chosen during onboarding.** `SET-09` moves out of P2 and becomes part of the first-run flow, so a position always exists before the first detection.

Consequences: `KID-01` budgets four onboarding screens and they are already used — the region picker has to share the permissions screen rather than add a fifth. It also needs to work for a child who declines GPS entirely (pick on a map, or by place name), and the wording matters: this is the moment a parent decides whether to trust the app with location, so it belongs next to the `KID-08` parent notice.

**G. What is a grid cell? — ✅ settled**

> **Decided: 0.1°, and the same grid everywhere in the app.** 11.1 km of latitude everywhere, ~7 km of longitude at this latitude. It satisfies `NFA-08`, and it is what the weather cache already rounds to (`(lat * 10).round() / 10`). **`PKT-13`'s "new place" bonus uses the same grid** — the specification's separate 5 km there would have been a second definition of "a different place" for no benefit. One notion of "roughly here", used by the rarity scale, the place bonus and the weather cache alike.

> **Decided: the position is re-checked every few minutes, but the scale is rebuilt only when the cell actually changes.** A cheap position read costs almost nothing; the 48 inferences then run practically never. This is what makes the cell belong to the *detection* rather than the session, and it fixes the walk-to-school case — a bird heard at the end of the walk is valued where it was heard, not where the walk started. The same cell change is the natural trigger for `PKT-13` later.

**Why the app needs a cell at all — in order of weight:**

1. **Privacy (`NFA-08`).** Every `ScoreEvent` carries a location. Un-coarsened, a year of them is a movement history of a child. This reason alone settles it, independent of anything below.
2. **It defines when the scale is recomputed.** Building a scale costs 48 ONNX inferences. Without a cell there is no natural answer to "has the child moved enough to matter?" — you would have to invent a distance rule. The cell *is* that rule, and it doubles as the cache key.
3. **Stability of the point values.** Weakest of the three, and worth stating accurately: the geo model is trained on aggregated eBird checklists and is far coarser than a kilometre, so a few hundred metres barely moves its output. What could still flip is a species sitting exactly on a tier boundary — the tiers are rank percentiles, so a hair's-breadth change in order can move one species one tier. Rare, small, and invisible to almost everyone — but unexplainable when it happens, which is what principle 6 objects to.

**Four things the decision implies, and each is easy to get wrong:**

1. **Drop the accuracy request, keep GPS.** *Decided.* `LocationService` currently defaults to `LocationAccuracy.high` (~10 m) — precision the 0.1° rounding throws away immediately, paid for in battery. **GPS stays as a source**; only the requested accuracy comes down, to roughly the 1 km class. That is still an order of magnitude finer than a 7–11 km cell, so cell assignment is never in doubt, and it lets the platform answer from a cached or network fix when one is good enough instead of waking the GPS chip every time. It is also the better privacy posture (`NFA-08`): the app never asks for a precision it has no use for. *Worth revisiting later whether `ACCESS_FINE_LOCATION` can be dropped for `ACCESS_COARSE_LOCATION` entirely — nothing left in Smartfinch needs metre-level position, and for a children's app that is a strong thing to be able to state.*
2. **Roughly every 5 minutes is enough.** A child on foot needs over an hour to cross a cell; in a car it is about ten minutes. A 5-minute check catches every realistic crossing without being a poll.
3. **Never block listening on a rebuild** (principle 7). Building the new scale takes 48 inferences. Keep using the current scale until the new one is ready, then switch — a detection during the rebuild is valued with the old cell, which is off by at most a few minutes and always explainable. Run the rebuild **in an isolate**: during a live session the UI has to hold 60 fps (`NFA-13`), and the existing Explore-screen code deliberately runs these inferences on the main isolate because there it happens once, on a loading screen.
4. **Keep a few cells cached, not one.** A child whose route crosses a boundary would otherwise rebuild the scale every few minutes, back and forth. A small LRU cache of the last handful of `(cell, geoWeek)` scales makes the pendulum case free.

> **What this fixes:** live mode today fetches the position once, at session start — there is no position stream (the only GPS tracker in the codebase belongs to Survey and is being deleted). Without this decision, "per detection" and "per session" would mean the same thing and the walk to school would be scored entirely with the scale from the front door. Points already awarded are untouched by a cell change, because `PKT-15` freezes them.

**H. Migration of detections that have no position — ✅ resolved: the case does not arise**

*This gap was written on a false premise and is withdrawn. Recording the reasoning, because the conclusion is worth keeping.*

The premise was that Smartfinch inherits BirdNET Live's saved sessions and has to score them retroactively. It does not. **Smartfinch ships under its own application ID and installs alongside BirdNET Live** (see the transition document, §8) — platform sandboxing means it cannot read the other app's files at all. There are no legacy detections, and `LOG-12` in its original sense has nothing to migrate.

That leaves exactly two paths by which data enters a Smartfinch install, and neither has the problem:

| Path | What happens | Position? |
|---|---|---|
| **Restore from backup** (`SET-07`) | A Smartfinch backup contains the `ScoreEvent` journal, and every event already carries its frozen base value, level, `geoWeek`, grid cell and threshold (`PKT-15`). **A restore reinstates; it does not recompute.** Nothing is looked up again, so nothing can be missing | Already inside every event |
| **Live detection** | A rarity level requires a position — and since `SET-09` moved into onboarding (gap F), a home region always exists as the fallback when GPS is unavailable | Always present |

**The rule that covers the remainder is already written and needs no exception:** no rarity level, no stars (2.3). A detection that somehow has no position scores nothing and is kept in the journal marked as outside scoring (`LOG-15`) — exactly the same treatment as a test-mode recording. No "lowest level" special case, no separate note type, one rule fewer to explain.

> **One consequence for `DAT-03`.** `recomputeAllScores()` re-derives multipliers and bonuses but never the base value. After a restore it must therefore be safe to run over reinstated events *without* touching them — the frozen fields are the authority, and the recomputation only rebuilds what sits on top. Worth an explicit test.

### Conflicts found in a full pass over the catalogue

*A fourth review, this time reading chapters 2–6 against each other rather than against the code — including chapter 3, which had not been checked before. Twelve findings, ordered by how much they cost to leave alone.*

**Four are now settled** (1, 2, 5, 6). The remaining eight are smaller: two badges that need redefining, two fairness problems, one data-model rule to reuse, and three editorial fixes. None blocks the MVP.

#### Real contradictions

**1. A rebalancing can take a child's level away. — ✅ fixed: levels ratchet.** `AUS-12` promises retroactive recomputation when rules change, and `DAT-03` makes it possible. But levels (3.5) are thresholds on the **total star count**, so a recomputation that lowers the total would drop the child a level and take the avatar stage with it (`AVA-02`) — a direct breach of principle 1, and the balancing *will* change. **Decided: store the highest level ever reached and never fall below it.** A recomputation may raise a level, never lower one. One column, and unbuildable retroactively once children have levels.

**2. Three titles existed twice. — ✅ fixed: the levels were renamed.** *Kenner*, *Spurenleser* and *Vogelkundler* were both achievements and levels, in two systems 3.1 defines as separate. **Decided: the levels give way**, and four more went with them — *Feldforscher*, *Artenkenner*, *Meisterlauscher* and *Vogelflüsterer* were human titles standing on a bird's life stages. The level ladder now runs egg → chick → … → migrant → old bird → legend, which is also what `AVA-02` needs, since the level *is* the avatar's stage of life. Expertise titles stay with the achievements. New table in 3.5.

**3. 3.4 still describes the collection as a toggle.** "A second toggle in the collection alongside All species / My collection" was written before Collection and Explore became separate areas (`SAM-02`). Same for the sentence in 3.4 that assumes a shared list. Wording only, but it is the kind of leftover that gets implemented literally.

**4. `LIVE-16` has the life-list problem from `DAT-11`.** Manually adding a species seen rather than heard awards 0 stars but fills the collection. If it also writes to the life list, the first-find ×3 for that species is burned — the same silent punishment `DAT-11` guards against for test-mode detections. **Fix: use the same rule.** A manually added species fills the collection but does not touch the life list, so the day it is actually *heard* it still counts as a first find.

#### Terms used but never defined

**5. "Listened on a day" was used four times and defined nowhere. — ✅ settled.** `STAT-06` counts *active days* and the *longest streak*; three persistence achievements count consecutive days (3.3). **Decided: a day is active when it produced at least one scoring detection.** Not "app opened", not "session started". It is the only definition a child can check against their own journal, and it keeps "active" meaning "was outside and heard something" rather than "unlocked the phone". Belongs in `SET-11`.

**6. Does a test-mode day break a streak? — ✅ settled: yes.** *Decided: non-scoring detections are excluded, without an exception for the streak.* A day spent entirely in test mode is not an active day. The argument against was principle 1 — but this is not a punishment applied *to* the child: the setting sits behind Advanced settings, a warning and a confirmation, and it is normally an adult who changes it. One rule with no exceptions also beats a rule with a special case, for principle 6. **The condition is that `SET-13` says so at the moment of change**, which it now does — otherwise a child discovers days later that a streak quietly stopped, and *that* would be the hidden punishment.

**7. *Frühlingsbote* lost its definition with the off-list case.** "A species detected that is unusually scarce here this week" was the off-list case, removed in 2.3. It can be redefined against the annual curve the app already has: **the species is currently at least two levels rarer than at its own yearly peak** (`f_week` versus `f_year`). That reads exactly as the badge intends — a bird that is here earlier than it should be — and the data is already loaded for `SAM-15`.

**8. *Sensation!* is no longer sensational.** "1 species at the highest level" was the off-list case too. Under rank-relative levels the top tier holds roughly a tenth of the local species (2.1), so this fires in the first week. Recommendation: make it the *tenth* species from the top tier, or tie it to the year list instead.

#### Fairness and balance

**9. The weekly target of 5,000 stars is either automatic or unreachable.** The balancing check in 2.8 has an ordinary garden week at 6,350 stars — so for most children the badge fires without effort, while a balcony child never reaches it. Both failure modes at once. Recommendation: make it relative to the child's own recent weeks, or drop it.

**10. *Weitgereist* (3 different places in a week) needs a car.** With 0.1° cells (D23 / gap G) three cells in one week means real travel. For a child without a lift it is unreachable — principle 3. Recommendation: two cells, or count it per month rather than per week.

**11. *Schlechtwetterheld* is P3 in 3.2 and P2 in the catalogue.** `AUS-11` was raised when the weather service was kept; 3.2 was not updated. Editorial, but the two tables disagree.

**12. Two different "no gamification" states will exist.** `SET-05` (observation mode, P2) and `PKT-20` (scoring paused) both stop the scoring, by different routes and with different intent — one is a preference, the other a consequence. Decide before `SET-05` is built whether observation mode simply *is* `PKT-20` with a friendlier name, or a genuinely separate state that also hides the star UI. One mechanism with two entry points is much cheaper than two mechanisms.

> **One editorial note that is not a conflict:** `AVA-05` justifies the preset avatar names as avoiding "free-text moderation issues", while `LOG-13` now lets a child type any place name. Both are right, because both stay local and nothing is ever transmitted (`KID-07`). The *reasoning* in `AVA-05` is what needs updating, not the requirement.

**New open questions raised by the codebase review:**

6. **Which locales get child-register species profiles?** Twelve UI locales are being kept, but rewriting 130 species profiles in a child's register in twelve languages is a different order of magnitude from translating buttons. Recommendation under SET-10: German first, English second.
7. **What happens to the Windows build?** It exists, works, and is not in this document's target platforms. Decide explicitly — drop it, or keep it unmaintained and say so.
8. **How often is upstream merged?** Smartfinch stays a fork with periodic merges from BirdNET Live. Monthly, or on every model bump; quarterly is how a fork silently becomes a hard fork. Strategy in the transition document, §7.

---

## 10. Sources

- [BirdNET-Analyzer — Creating Your Own Species List](https://birdnet-team.github.io/BirdNET-Analyzer/best-practices/species-lists.html) — how the location- and week-specific species list is generated
- [BirdNET-Analyzer Discussion #234 — Species range model details](https://github.com/birdnet-team/BirdNET-Analyzer/discussions/234) — the range model's output as an eBird checklist frequency, 0–100
- [BirdNET-Analyzer — species-lists.rst (documentation source)](https://github.com/birdnet-team/BirdNET-Analyzer/blob/main/docs/best-practices/species-lists.rst)
- [Kahl et al., BirdNET: A deep learning solution for avian diversity monitoring](https://www.sciencedirect.com/science/article/pii/S1574954121000273) — the foundational paper
- [Dachverband Deutscher Avifaunisten — most common breeding birds in Germany](https://www.dda-web.de/voegel/haeufigste-brutvoegel) — population figures used as a plausibility check on the level banding
