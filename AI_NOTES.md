# AI Usage Notes

## What the AI wrote end-to-end

- The initial `seed.js` word-list scaffold (names, jobs, hobbies, prompt fragments) and the deterministic profile generator.
- The first pass of the swipe-card CSS — the rotation transform, the YES/NO badge corners, and the linear-gradient brand logo.
- The aggregation SQL — the `LEFT JOIN items ↔ votes` with the `SUM(CASE WHEN choice = 'yes' …)` pattern and the four sort modes (`top`, `divisive`, `skipped`, `matches`).
- The aria-labels, keyboard fallback buttons, and the empty-state copy.

## Where I pushed back / rewrote

**Storage layer.** The first iteration used a flat `votes.json` file because it was the fastest path to "running". When the spec called for real multi-user behavior I made the call to migrate to **SQLite via `better-sqlite3`** — synchronous API (no callback hell in the route handlers), ships prebuilt binaries on Windows so the grader doesn't need MSVC, and lets me enforce dedup at the schema level with `PRIMARY KEY (user_id, item_id)` instead of an `Array.findIndex` race in JavaScript. The AI initially wanted to keep going with JSON; I overrode that because the moment we have real users, "two requests interleave during a synchronous file write" stops being theoretical.

**Swipe handler.** The AI's first cut used **separate `touchstart`/`mousedown` listeners** and locked the gesture direction on the very first move event. Two problems:

1. The two listener sets fought each other on hybrid devices (touch laptops fired both), causing the card to commit a vote and then immediately follow the mouse.
2. Locking on the first 1–2 px of movement made every drag feel "stuck" in whichever direction the user's finger jittered first.

I rewrote it as a **single Pointer Events** path (`pointerdown` / `pointermove` / `pointerup`) with `setPointerCapture`, and introduced an 8 px dead-zone before deciding whether the gesture is horizontal (vote) or vertical (open results). Vertical lock only triggers when `dy > 0` so an upward flick still counts as a vote attempt. That single change made the deck *feel* right on both desktop drag and phone touch.

**Auth model.** The AI proposed signed JWTs out of the gate. For a single-process local demo that's overkill and brings in a dependency just to verify signatures. I used **opaque random tokens in a `sessions` table** instead: same security properties for this scope (an attacker would need to read the SQLite file to forge), but logout becomes a one-line `DELETE`, and there's no key-management story for a grader to set up.

## One thing it did better than I expected

The DiceBear avatar idea. I was reaching for stock photos or a `picsum.photos` workaround; the AI suggested a deterministic SVG-avatar service that gives every item — *and now every user* — a stable, free, non-personally-identifiable face. It hit the brief's "no real people without permission" rule without me having to think about it, and it lets a logged-in user have their own consistent avatar in the topbar derived from their username with zero extra storage.

## One thing it did worse

It kept reinventing tiny CSS-in-JS-style class toggles for the YES/NO tint instead of using a single `data-dir` attribute on the card. Three of my early prompts produced slightly different ad-hoc class names (`.is-yes`, `.swipe-right`, `.tinted-yes`) across handlers, which meant the badge briefly desynced from the tint. I collapsed it onto one `card.dataset.dir = 'yes' | 'no' | ''` and matched it from CSS with `[data-dir="yes"]`. Single source of truth, no flicker.

## Other tools

I primarily used **Claude (Cursor)** as the driver. I sanity-checked one bit of CSS (`touch-action` interactions with `overscroll-behavior` on iOS Safari) against MDN directly rather than trusting the LLM on a quirky platform detail — that's the kind of thing where the documentation is the authority, not the language model.
