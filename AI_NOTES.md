# AI Usage Notes

## What the AI wrote end-to-end

- The initial `seed.js` word-list scaffold (names, jobs, hobbies, prompt fragments) and the deterministic profile generator.
- The first pass of the swipe-card CSS — the rotation transform, the YES/NO badge corners, and the linear-gradient brand logo.
- The aggregation SQL — the `LEFT JOIN items ↔ votes` with the `SUM(CASE WHEN choice = 'yes' …)` pattern and the four sort modes (`top`, `divisive`, `skipped`, `matches`).
- The aria-labels, keyboard fallback buttons, and the empty-state copy.
- The chat-message bubble CSS (iMessage-style accent-vs-neutral split, 30-minute time dividers) and the per-conversation `CTE` SQL that builds the conversation list with last-message preview and unread count.
- The Feather-style inline SVGs for the topbar icon buttons.

## Where I pushed back / rewrote

**Storage layer.** The first iteration used a flat `votes.json` file because it was the fastest path to "running". When the spec called for real multi-user behavior I made the call to migrate to **SQLite via `better-sqlite3`** — synchronous API (no callback hell in the route handlers), ships prebuilt binaries on Windows so the grader doesn't need MSVC, and lets me enforce dedup at the schema level with `PRIMARY KEY (user_id, item_id)` instead of an `Array.findIndex` race in JavaScript. The AI initially wanted to keep going with JSON; I overrode that because the moment we have real users, "two requests interleave during a synchronous file write" stops being theoretical.

**Swipe handler.** The AI's first cut used **separate `touchstart`/`mousedown` listeners** and locked the gesture direction on the very first move event. Two problems:

1. The two listener sets fought each other on hybrid devices (touch laptops fired both), causing the card to commit a vote and then immediately follow the mouse.
2. Locking on the first 1–2 px of movement made every drag feel "stuck" in whichever direction the user's finger jittered first.

I rewrote it as a **single Pointer Events** path (`pointerdown` / `pointermove` / `pointerup`) with `setPointerCapture`, and introduced an 8 px dead-zone before deciding whether the gesture is horizontal (vote) or vertical (open results). Vertical lock only triggers when `dy > 0` so an upward flick still counts as a vote attempt. That single change made the deck *feel* right on both desktop drag and phone touch.

**Auth model.** The AI proposed signed JWTs out of the gate. For a single-process local demo that's overkill and brings in a dependency just to verify signatures. I used **opaque random tokens in a `sessions` table** instead: same security properties for this scope (an attacker would need to read the SQLite file to forge), but logout becomes a one-line `DELETE`, and there's no key-management story for a grader to set up.

## Where the AI got it almost-right and missed edge cases I had to catch

The realtime / chat layer was built in roughly six iterative passes, and the AI got the happy path right each time but kept missing one piece of cache state I'd written into the system. Two of these were caught only because I drove a two-window manual test after every change, and they're worth calling out because they're the kind of latent bugs an LLM-generated patch tends to ship:

1. **Detail modal silently bailed on the viewer's own profile.** When I added user-published profiles, the AI correctly filtered the owner's row out of `GET /api/items` so they wouldn't see themselves in the deck. Side effect I had to discover: `itemsById` is populated from that endpoint, so when the user clicked their own row in the **Results** list, `openProfile(itemId)` did `if (!item) return;` and silently did nothing. Fix involved both adding `description` to `/api/results` and falling back to `lastResults` in the modal opener. The AI didn't anticipate this because it treated the deck and the results list as two separate views with two separate data caches, instead of one shared world.

2. **Live profile updates patched the deck cache, not the results cache.** The websocket `profile:updated` handler was happily updating `items` / `itemsById` so the deck refreshed in real time. The Results view, however, renders from a parallel cache `lastResults` that is only refreshed by the 30s poll. Two browser windows, one editing a profile, the other on Results: the row sat there with the old avatar for up to 30 seconds. Fix was a four-line patch into the same handler, but the bug only surfaced because I tested by *staying on Results* rather than going back to the deck. A reminder that "incremental cache invalidation" mistakes are the LLM's natural failure mode — it remembers the cache it just wrote and forgets the other one.

3. **Commit history rewriting + the `Co-authored-by: Cursor` trailer.** This wasn't a code bug, but it's worth recording. When I asked the AI to split a single "all functionality" commit into per-subsystem commits, the local `git log` showed the author email I expected (`jiajian.liu@sjsu.edu`), but GitHub displayed the commits as authored by a *different* personal account because the email it had been using mapped to that other account. We chased this with `git filter-branch` to set the right author identity, then I noticed the Cursor-injected `Co-authored-by: Cursor <cursoragent@cursor.com>` trailer was missing from the rewritten commits — turns out passing `-c user.name=… -c user.email=…` inline to `git commit` was bypassing whatever path Cursor uses to inject the trailer. We added the trailer back in another `filter-branch` pass and now every commit deliberately credits both me and the AI.

## Build cadence — what the timeline looked like

Roughly: foundation in one sitting (six commits, subsystem by subsystem — scaffolding → schema → API → HTML/CSS → JS → docs), then features grew organically over the next session, one focused commit per feature. The chat layer came last because it built on the websocket layer, which built on the wave feature, which built on the profile detail modal. None of those would have been pleasant to write in one go; the iterative path with manual tests in between was where the AI saved real time.

## One thing it did better than I expected

The DiceBear avatar idea. I was reaching for stock photos or a `picsum.photos` workaround; the AI suggested a deterministic SVG-avatar service that gives every item — *and now every user* — a stable, free, non-personally-identifiable face. It hit the brief's "no real people without permission" rule without me having to think about it, and it lets a logged-in user have their own consistent avatar in the topbar derived from their username with zero extra storage.

The conversation-list query also came out unexpectedly clean — a single CTE that collapses each conversation to its latest message + unread count + the partner's profile preview, all in one round-trip. I would have written that as three sequential queries plus a JS-side merge; the AI's one-shot CTE is both faster and easier to read.

## One thing it did worse

It kept reinventing tiny CSS-in-JS-style class toggles for the YES/NO tint instead of using a single `data-dir` attribute on the card. Three of my early prompts produced slightly different ad-hoc class names (`.is-yes`, `.swipe-right`, `.tinted-yes`) across handlers, which meant the badge briefly desynced from the tint. I collapsed it onto one `card.dataset.dir = 'yes' | 'no' | ''` and matched it from CSS with `[data-dir="yes"]`. Single source of truth, no flicker.

The same "two parallel state caches" failure mode also showed up again on the chat client side — the AI's first pass appended the user's own outgoing message to the chat log optimistically *and* echoed it back via the websocket, which would have produced duplicate bubbles. We fixed that by having the server fan a `message` frame out to *all* of the sender's sockets too, so the optimistic append was deleted and there's one render path for both directions of message. Simpler in the end, but only after one round of "wait, why is everything doubled?".

## Other tools

I primarily used **Claude (Cursor)** as the driver. I sanity-checked one bit of CSS (`touch-action` interactions with `overscroll-behavior` on iOS Safari) against MDN directly rather than trusting the LLM on a quirky platform detail — that's the kind of thing where the documentation is the authority, not the language model. The `ws` package API I cross-checked against its README on npm rather than letting the AI guess at the upgrade-handshake helper signature, because that one is small enough to read end-to-end in 5 minutes.

I also ran this write-up and the README through the same assistant for grammar and clarity after drafting them by hand.
