---
name: Klora Fitness
description: A coaching gym tracker drawn as a rack of coated pastel hand-weights, where load is colour.
colors:
  hot-rose: "#cf3a76"
  hot-rose-deep: "#b02a62"
  hot-rose-night: "#e06d9b"
  blush-ground: "#fbeff4"
  blush-raised: "#fdf6f9"
  blush-slab: "#fffbfc"
  blush-slab-2: "#f7e6ed"
  blush-slab-3: "#efd5e0"
  plum-ink: "#3a1d2c"
  plum-night: "#1a0f16"
  plum-night-raised: "#22141d"
  plum-slab: "#2c1b26"
  plum-slab-2: "#3a2532"
  plum-slab-3: "#4a3040"
  night-ink: "#fcf0f5"
  rack-rose: "#f7c3d6"
  rack-rose-ink: "#5c1033"
  rack-lilac: "#d9cbf5"
  rack-lilac-ink: "#33206b"
  rack-mint: "#bfe7d4"
  rack-mint-ink: "#114a33"
  rack-butter: "#f8e6a0"
  rack-butter-ink: "#5a4100"
  rack-peach: "#fbd2bd"
  rack-peach-ink: "#6b2a0c"
  rack-sky: "#c6e0f7"
  rack-sky-ink: "#123a63"
typography:
  display:
    fontFamily: "Rubik, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, system-ui, sans-serif"
    fontSize: "clamp(38px, 11vw, 54px)"
    fontWeight: 600
    lineHeight: 0.98
    letterSpacing: "-0.035em"
  headline:
    fontFamily: "Rubik, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, system-ui, sans-serif"
    fontSize: "34px"
    fontWeight: 600
    lineHeight: 1.06
    letterSpacing: "-0.022em"
  title:
    fontFamily: "Rubik, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, system-ui, sans-serif"
    fontSize: "22px"
    fontWeight: 600
    lineHeight: 1.1
    letterSpacing: "-0.018em"
  title-sm:
    fontFamily: "Rubik, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, system-ui, sans-serif"
    fontSize: "17px"
    fontWeight: 500
    letterSpacing: "-0.01em"
  numeral:
    fontFamily: "Rubik, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, system-ui, sans-serif"
    fontSize: "28px"
    fontWeight: 600
    lineHeight: 1
    letterSpacing: "-0.03em"
    fontFeature: "tnum"
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', Roboto, system-ui, sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.29
    letterSpacing: "-0.01em"
    fontFeature: "tnum"
  body-sm:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', Roboto, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.35
  label:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', Roboto, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 600
    letterSpacing: "0.005em"
rounded:
  sm: "12px"
  md: "16px"
  slab: "22px"
  lg: "22px"
  xl: "28px"
  tabbar: "30px"
  pill: "999px"
spacing:
  rack-gap: "6px"
  tile-gap: "8px"
  list-gap: "10px"
  slab-pad: "18px"
  row-pad: "12px 14px"
components:
  button-primary:
    backgroundColor: "{colors.hot-rose}"
    textColor: "{colors.blush-slab}"
    rounded: "{rounded.pill}"
    padding: "14px 20px"
    typography: "{typography.body}"
  button-primary-hover:
    backgroundColor: "{colors.hot-rose-deep}"
  button-secondary:
    backgroundColor: "{colors.blush-slab-2}"
    textColor: "{colors.plum-ink}"
    rounded: "{rounded.pill}"
    padding: "14px 20px"
  button-secondary-hover:
    backgroundColor: "{colors.blush-slab-3}"
  button-sm:
    rounded: "{rounded.pill}"
    padding: "8px 15px"
  card:
    backgroundColor: "{colors.blush-slab}"
    textColor: "{colors.plum-ink}"
    rounded: "{rounded.slab}"
    padding: "18px"
  today-pill:
    backgroundColor: "{colors.rack-rose}"
    textColor: "{colors.rack-rose-ink}"
    rounded: "24px"
    padding: "18px 18px 18px 16px"
    height: "84px"
  today-pill-done:
    backgroundColor: "{colors.rack-mint}"
    textColor: "{colors.rack-mint-ink}"
  today-pill-live:
    backgroundColor: "{colors.rack-peach}"
    textColor: "{colors.rack-peach-ink}"
  today-pill-rest:
    backgroundColor: "{colors.rack-lilac}"
    textColor: "{colors.rack-lilac-ink}"
  standing-badge:
    backgroundColor: "{colors.rack-butter}"
    textColor: "{colors.rack-butter-ink}"
    rounded: "{rounded.pill}"
    padding: "4px 10px"
    typography: "{typography.label}"
  standing-badge-hot:
    backgroundColor: "{colors.hot-rose}"
    textColor: "{colors.blush-slab}"
  initials-weight:
    backgroundColor: "{colors.rack-peach}"
    textColor: "{colors.rack-peach-ink}"
    rounded: "{rounded.md}"
    size: "46px"
  rack-tile:
    backgroundColor: "{colors.rack-mint}"
    textColor: "{colors.rack-mint-ink}"
    rounded: "{rounded.slab}"
    padding: "12px 12px 11px"
  input:
    backgroundColor: "{colors.blush-slab}"
    textColor: "{colors.plum-ink}"
    rounded: "{rounded.md}"
  segmented:
    backgroundColor: "{colors.blush-slab-2}"
    rounded: "{rounded.pill}"
    padding: "3px"
  tab-bar:
    backgroundColor: "{colors.blush-slab}"
    rounded: "{rounded.tabbar}"
    padding: "8px 6px 9px"
  start-plate:
    backgroundColor: "{colors.hot-rose}"
    textColor: "{colors.blush-slab}"
    rounded: "{rounded.pill}"
    size: "60px"
  message-mine:
    backgroundColor: "{colors.rack-rose}"
    textColor: "{colors.rack-rose-ink}"
    rounded: "20px"
    padding: "10px 14px"
  message-theirs:
    backgroundColor: "{colors.blush-slab-2}"
    textColor: "{colors.plum-ink}"
    rounded: "20px"
    padding: "10px 14px"
  trainer-note:
    backgroundColor: "{colors.rack-butter}"
    textColor: "{colors.rack-butter-ink}"
    rounded: "18px"
    padding: "12px 14px"
---

# Design System: Klora Fitness

## Overview

**Creative North Star: "The Pastel Dumbbell Rack"**

Load is colour. Klora is drawn as a rack of coated hand-weights: every tier of meaning (a client, a standing, a day, a session state) is one matte neoprene pastel with its own dark ink, and every surface is the moulded vinyl those weights are made of. Fills are flat, each carries a thin top light along its upper edge and a soft shadow where it rests on the blush ground. Nothing is outlined for decoration; separation comes from fill and resting shadow.

The world has two lights. Blush (default, light theme) is a bright gym floor: a pale pink ground, near-white slabs, plum ink. Plum night (dark theme) is the same rack under low light: a deep aubergine ground on which the pastels glow; the tier fills keep their daytime values in both themes. One hot rose is reserved for action and "now": Start, the primary button, the selected tab, the client who needs the trainer, the unread count. The system refuses both the near-black neon fitness dashboard and the beige wellness minimal.

The density is phone-first and generous: large tappable pills and slabs, a floating tab bar, Rubik moulded numerals for anything counted. Pressing anything settles it: it sinks a pixel and its shadow tightens, like a weight set down on a mat.

**Key Characteristics:**
- Six pastel rack tiers (rose, lilac, mint, butter, peach, sky), each a fill-plus-ink pair that travels together.
- One hot rose for action and "now", never decoration.
- Moulded vinyl slabs: flat fill, inset top light, soft resting shadow, bottom lip on tier-filled pills.
- Pills everywhere you press; rounded slabs (22-28px) for everything that holds content.
- Rubik (self-hosted variable, 300-900) for headings and numerals; the platform face for reading text.
- Press-and-settle: 1px sink plus a tighter shadow on every pressable.

## Colors

A blush-and-plum neutral world carrying six matte pastel tiers and a single hot rose.

### Primary
- **Hot Rose** (`hot-rose`): the action colour. Primary buttons, the Start weight-plate, the active tab, the Start tag on today's pill, text-button actions, focus rings, caret and selection tint, the "Needs you" badge, the ring on a client row that needs attention, unread counts. Pressed and hovered it deepens to **Deep Rose** (`hot-rose-deep`) on blush and lifts to **Night Rose** (`hot-rose-night`) on plum. Its soft wash (15% mix) and line (36% mix) are derived with `color-mix`, never separately picked.

### Secondary: the rack tiers
Each tier is a pastel fill and a dark ink of the same hue. They are identical in both themes.
- **Rose Weight** (`rack-rose` / `rack-rose-ink`): planned days, the default tier, the trainer card on the client's side, the user's own chat bubbles.
- **Lilac Weight** (`rack-lilac` / `rack-lilac-ink`): rest days, noted days, "New" standing, the "All clients" tile.
- **Mint Weight** (`rack-mint` / `rack-mint-ink`): done. Trained days in the week rack and day minirack, finished sessions, "On track", "Trained this week".
- **Butter Weight** (`rack-butter` / `rack-butter-ink`): trainer notes, "Drifting".
- **Peach Weight** (`rack-peach` / `rack-peach-ink`): in-progress sessions, "Gone quiet".
- **Sky Weight** (`rack-sky` / `rack-sky-ink`): the sixth client tier; client identity colours cycle tiers 0-5.

### Neutral
- **Blush Ground** (`blush-ground`): the light page.
- **Blush Raised** (`blush-raised`): sheets, dialogs, invite fields, inputs inside a panel.
- **Blush Slab / Slab 2 / Slab 3** (`blush-slab`, `blush-slab-2`, `blush-slab-3`): card fill; quiet fills (segmented track, empty week capsule, the other person's bubble); pressed/hover fill, scrollbar, sheet grab.
- **Plum Ink** (`plum-ink`): all light-theme text. Secondary text is plum ink at 70%, tertiary at 54%, disabled at 20%; separators at 13%.
- **Plum Night** (`plum-night`, `plum-night-raised`, `plum-slab`, `plum-slab-2`, `plum-slab-3`): the dark theme's ground, raised and slab steps.
- **Night Ink** (`night-ink`): dark-theme text, with the same alpha ladder (70 / 48 / 20%).

### Named Rules
**The One Rose Rule.** Hot rose means "press this" or "this is now". If an element is neither, it is not hot rose; use the rose tier instead.

**The Fill-Carries-Ink Rule.** Text on a tier fill is always that tier's ink, never grey and never plum. A tier is applied as a pair (fill + ink) or not at all.

**The Same-Weights-At-Night Rule.** Tier fills do not darken for the dark theme. On plum, a client row takes only a 9% mix of its tier (22% on blush), but full tier surfaces (today's pill, rack tiles, badges, avatars) keep their daytime pastel.

## Typography

**Display Font:** Rubik, self-hosted variable woff2 (300-900), with the platform system stack as fallback
**Body Font:** the platform face (-apple-system, SF Pro Text, Segoe UI, Roboto, system-ui)

**Character:** Rubik's softened corners read as moulded rubber numerals stamped into a weight; the platform face keeps reading text quiet and native. Numbers are tabular everywhere.

### Hierarchy
- **Display** (600, 38-54px fluid, 72px on desktop, 0.98): the sign-in hero only. The rose-coloured word inside it is the single accent.
- **Headline** (600-700, 34px, 30px under 420px, 1.06, -0.022em): screen titles ("Hi Klora", "Clients"); client name on the detail page at 30px.
- **Title** (600, 21-22px, -0.016 to -0.02em): today's pill title, trainer card name, sheet and panel headings.
- **Title Small** (500, 17-18px, -0.01em): row names, assignment titles, tappable card titles.
- **Numeral** (600, 28px, 1.0, -0.03em): rack tile counts, week-day numbers, session dates (19px), invite codes (17px, +0.12em).
- **Body** (400, 17px, 1.29): reading text; lede at 17px / 1.4 capped at 34ch; descriptive sentences 15px / 1.45.
- **Body Small** (400, 13px, 1.35-1.4): row subtitles, meta lines, footnotes, in secondary ink.
- **Label** (600, 12px): badges, tile labels, tab labels (10.5px).

### Named Rules
**The Moulded Numeral Rule.** Anything counted (days, kilos, clients, sessions, codes) is set in Rubik. Sentences are not.

**The Bold Word Rule.** Inside a secondary-ink sentence, the fact that matters is a Rubik 600 word in full ink, not a separate stat block.

## Layout

A single phone column (max 560px, centred) is the base on every screen. The header sits top-left with round icon buttons at the right. Content stacks as slabs with 10-16px between them. The week rack is seven equal capsules with a 6px gap. The trainer's standing rack is a four-up grid of tiles (8px gap) that drops to two-up under 360px. Client rows stack with 10px gaps.

The tab bar floats 12px in from each side and 10px above the safe area; content reserves 104px at the bottom for it. At 1000px and wider the tab bar becomes a 540px centred island 18px from the bottom, the trainer roster widens to 1000px and racks clients two-up, and sign-in becomes a two-column grid (1.1fr / 0.9fr, 56px gap) with the hero on the left and the panel on the right.

## Elevation & Depth

Depth is moulded, not floating. Each slab has a 1px inset top highlight (the light catching the vinyl) and a soft, negatively spread shadow that pools beneath it, tinted plum-rose on blush and black on plum. Tier-filled pills add a darker inset bottom lip (3-5px at 5-8% black) so they read as solid weights, not flat stickers. Only two shadow heights exist, plus the rose glow under action elements.

### Shadow Vocabulary
- **Rest** (`0 1px 0 rgba(255,255,255,.9) inset, 0 1px 2px rgba(58,29,44,.05), 0 10px 24px -16px rgba(120,40,80,.32)` on blush): cards, tiles, rows, chips, icon buttons, the selected segment.
- **Lift** (`0 1px 0 rgba(255,255,255,.9) inset, 0 2px 4px rgba(58,29,44,.05), 0 20px 40px -20px rgba(120,40,80,.40)` on blush): the tab bar, sign-in panel, timer, toast, hovered client rows.
- **Rose glow** (`0 10px 22px -10px` hot rose at 70%): primary buttons, the selected chip, the Start plate, the Start tag.
- **Weight lip** (`inset 0 1px 0 rgba(255,255,255,.5), inset 0 -5px 0 rgba(0,0,0,.06)`): today's pill, the trainer card, rack tiles (-4px), initials weights (-3px).

### Named Rules
**The Press-and-Settle Rule.** Every pressable sinks 1px on press (pills also scale to 0.975, tiles to 0.97, the Start plate drops 2px and scales to 0.94) and its shadow tightens: the rose glow shrinks to `0 4px 10px -6px`, the weight lip thins from 5px to 2px. Easing is `cubic-bezier(.16,1,.3,1)` over 140ms. Nothing lifts on press.

**The Ring-Not-Raise Rule.** Selection and attention are drawn as an inset ring (2px in the element's ink, or hot rose for "needs you"), never by lifting the element higher.

## Shapes

Everything pressable is a full pill (999px): buttons, chips, tags, badges, segmented controls, search fields, week capsules, the compose field (24px). Everything that holds content is a generously rounded slab: cards and rows 22px, list items 18px, tiles 20-22px, today's pill 24px, panels, sheets and empty states 28px, the tab bar 30px. Initials weights are rounded squares (16px at 46px, 22px at 64px). Chat bubbles are 20px with the tail corner cut to 6px. There are no hairline borders on slabs; inputs use a 1px inset separator ring that becomes a 2px rose ring on focus.

## Components

### Buttons
Soft rubber pills that settle when pressed.
- **Shape:** full pill (999px), 14px 20px; small 8px 15px.
- **Primary:** hot rose fill, white text, rose glow beneath; hover deepens to Deep Rose.
- **Secondary:** Blush Slab 2 fill, plum ink; hover Blush Slab 3.
- **Ghost / Plain:** rose text, no fill; on press a 15% rose wash.
- **Focus:** 2.5px hot rose outline, 3px offset.

### Chips and Badges
- **Chips:** Blush Slab fill with the rest shadow; selected chip gains the rose glow.
- **Standing badges:** 12px / 600 pills (4px 10px) in a tier fill with its ink and a leading icon; "Needs you" is the hot variant (hot rose, white).

### Cards / Containers
- **Corner Style:** 22px (cards, rows), 28px (panels, empty states, trainer card).
- **Background:** Blush Slab; client rows mix 22% of their tier into the slab.
- **Shadow Strategy:** Rest at rest, Lift on hover; see Elevation.
- **Internal Padding:** 18px cards, 12px 14px rows.

### Inputs / Fields
- **Style:** Blush Slab fill (Blush Raised inside a panel), 16px radius, 1px inset separator ring; search fields are pills.
- **Focus:** inset ring thickens to 2px hot rose; caret is hot rose.

### Navigation
- **Tab bar:** one floating 30px-radius slab with the Lift shadow, labels 10.5px / 600 in tertiary ink; the active tab turns hot rose. On desktop it is a 540px centred island.
- **Start plate:** a 60px hot rose disc seated 30px above the bar, drawn face-on as a weight plate with a lighter inner ring and a darker moulded groove, separated from the bar by a 5px ground-coloured collar. While recording it turns orange.
- **Segmented control:** pill track in Blush Slab 2, the selected segment a Blush Slab pill with the rest shadow.

### Week Rack (signature)
Seven pill capsules in a row. Empty days are Blush Slab 2; planned days a 55% rose-tier mix with a 14x4px rose bar; done days full mint with mint-ink numerals and a mint-ink bar; noted days lilac. Today is ringed with a 2px inset plum (label) ring and its numeral goes to 700. A miniature version (7 capsules, 8x16px, 3px gap) sits on every client row.

### Today Pill (signature)
The fattest pill on Home (24px radius, min 84px tall): a full tier weight. Planned is rose, done mint, in progress peach, rest lilac. Its icon sits in a 40px white-wash rounded square, title is Rubik 22px in the tier ink, and its action tag is an inverted pill (ink fill, tier text); when the session can start, the tag is hot rose with the rose glow.

### Initials Weight and Rack Tiles
Client identity is a 46px rounded-square capsule in the client's tier with Rubik 600 initials in the tier ink; stacked avatars overlap by 10px with a 3px rose collar. The trainer's standing rack is four tier tiles, each a big Rubik count over a 12px label; the active filter is ringed in its own ink.

### Messages and Notes
The user's bubbles are the rose tier, the other person's are Blush Slab 2; notes from the trainer are butter slabs (18px radius).

## Do's and Don'ts

### Do:
- **Do** give every tier of meaning (client, standing, day state, session state) one rack colour, and apply its fill and ink together.
- **Do** keep hot rose for Start, primary actions, the active tab, "needs you" and unread counts only.
- **Do** make every pressable a pill or a 22-28px slab that sinks 1px and tightens its shadow on press.
- **Do** set counts, dates, weights and headings in Rubik 600; reading text in the platform face at 17px.
- **Do** show selection and attention with a 2px inset ring, not a higher shadow.
- **Do** keep tier fills at their daytime values on plum night; only mixed row tints drop to 9%.

### Don't:
- **Don't** put grey or plum text on a tier fill; use the tier's ink.
- **Don't** use hot rose as a tier, a decorative fill or a data colour; the rose tier exists for that.
- **Don't** draw hairline borders around slabs; separation is fill plus resting shadow.
- **Don't** add a third shadow height or lift elements on press.
- **Don't** drift toward a near-black neon dashboard or a beige wellness minimal; the ground is blush or plum.
- **Don't** introduce small tracked uppercase labels above headings; the only tracked uppercase line in the build is the wordmark's "Fitness" lockup.
