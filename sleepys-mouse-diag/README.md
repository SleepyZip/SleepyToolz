# Sleepy's Mouse Diag

A Processing sketch for visualizing mouse input in real time — useful for
diagnosing flaky mouse hardware (double-click debounce, worn switches,
inconsistent scroll behavior) or just watching your own input habits.

## What it shows

- **Scroll tracer** — a crisp trail plotting scroll-wheel movement over time,
  with green/red bars marking scroll direction and a fading trail.
- **Mouse diagram** — a live diagram of the left/middle/right buttons showing
  press state, hold-time in milliseconds, and a flash on press. Double-clicks
  get a distinct outline flash so accidental double-clicks (a common sign of
  a dying switch) are easy to spot.
- **HUD** — running counts and timing info for quick reference.

## Running it

Requires [Processing](https://processing.org/download). Open
`SleepysMouseDiag_1_0.pde` in the Processing IDE and run.

## Contents

```
SleepysMouseDiag_1_0.7z    The sketch (extract to get the .pde source)
p5.js                      Vendored p5.js library file
```
