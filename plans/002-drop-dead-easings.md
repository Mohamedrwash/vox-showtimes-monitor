# 002 · tokens: drop dead easings

Severity: LOW · Category: Cohesion & tokens

## Problem

`site/css/tokens.css` defines `--ease-soft: cubic-bezier(0.16, 1, 0.3, 1)` — byte-identical to
`--ease-out` (same cubic-bezier), and `--ease-in: cubic-bezier(0.7, 0, 0.84, 0)` — unused
anywhere in `style.css` or `main.js`. Two names for one curve is a consolidation finding; a
dead token invites future misuse.

## Fix

In `site/css/tokens.css`, the motion block is:

```css
  --ease-out:     cubic-bezier(0.16, 1, 0.3, 1);
  --ease-in:      cubic-bezier(0.7, 0, 0.84, 0);
  --ease-in-out:  cubic-bezier(0.65, 0, 0.35, 1);
  --ease-soft:    cubic-bezier(0.16, 1, 0.3, 1);
```

Replace with:

```css
  --ease-out:     cubic-bezier(0.16, 1, 0.3, 1);
  --ease-in-out:  cubic-bezier(0.65, 0, 0.35, 1);
```

Keep `--ease-in-out` — it drives the loading-dot pulse.

## Verify

1. `rg -- "--ease-in|--ease-soft" site/` returns nothing.
2. Page renders; status dot still pulses while loading.
