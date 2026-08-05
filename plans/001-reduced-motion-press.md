# 001 · reduced-motion: drop press-scale movement

Severity: MEDIUM · Category: Accessibility

## Problem

Under `prefers-reduced-motion: reduce`, the site still animates `transform` (movement) on press:
`.btn:active`, `.chip:active`, `.copy-btn:active`, `.dialog-close:active` all scale the element.
The reduced-motion block in `site/css/style.css` (~line 870) covers the needle, ledger rows,
status dot, and dialog — but not press feedback. Per the motion audit, reduced motion means
fewer and gentler animations: keep color feedback, drop position changes.

## Fix

In `site/css/style.css`, inside `@media (prefers-reduced-motion: reduce)` (currently):

```css
@media (prefers-reduced-motion: reduce) {
  html { scroll-behavior: auto; }
  .ledger-row.enter { animation: none; opacity: 1; transform: none; }
  .dial-needle { transition: none; }
  .nav-status[data-state="loading"] .status-dot { animation: none; }
  .subscribe-dialog, .subscribe-dialog[open], .subscribe-dialog.closing { transition: opacity var(--dur-short) ease; }
}
```

Add after the `.dial-needle` line:

```css
  .btn:active, .chip:active, .copy-btn:active, .dialog-close:active { transform: none; }
```

Do not remove the `:active` declarations elsewhere — color transitions still apply via the
base transition rules.

## Verify

1. DevTools → Rendering → "Emulate prefers-reduced-motion: reduce".
2. Press a `.btn` / `.chip` / `.copy-btn` — no scale, color feedback only.
3. Without the emulation, press feedback still scales (regression check).
