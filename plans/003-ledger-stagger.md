# 003 · ledger rows: 40ms entrance stagger

Severity: LOW · Category: Cohesion & tokens (stagger) · additive polish

## Problem

When the ledger renders multiple films, all `.ledger-row.enter` rows animate in at once
(`rise` keyframe, 420ms ease-out, `animation-fill-mode: forwards`). A 30–80ms stagger reads
intentional on list entrances; everything-at-once reads flat once the watchlist grows past a
few films. Must remain decorative and never block interaction (bounded delay).

## Fix

In `site/js/main.js`, in the ledger render loop where rows are appended, after the row element
is built (it already receives the class `enter`), add an index-bounded delay:

```js
row.style.animationDelay = Math.min(idx * 40, 320) + "ms";
```

Apply the same delay to the film-title cell's `enter` only when `prefers-reduced-motion`
does not match — the CSS reduced-motion block already neutralizes `.ledger-row.enter`
(`animation: none`), so the delay style is inert there; no JS branch required.

Concretely, in `renderLedger`, the current loop appends one `ledger-row` per film and adds
class `enter`. Insert the `animationDelay` assignment keyed on the loop index.

## Verify

1. Temporarily set the snapshot to 3+ films (edit `site/data/showtimes.json` copies in
   `#snapshot-data`, or serve live JSON with 3 films), reload.
2. Rows rise one after another, 40ms apart, each 420ms — total ≤ 1.1s, no interaction blocked.
3. DevTools → Rendering → emulate reduced motion: rows appear instantly, no movement.
