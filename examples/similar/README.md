# Example: similar code in three "repos"

```
  repoA/src/blend.ts    blendRows   ┐
  repoB/web/mix.js      mixLines    ├─ the same routine, written four times
  repoC/blend.rs        blend_rows  │   (TypeScript, JavaScript, Rust, Python)
  repoC/blend.py        blend_rows  ┘
  repoA/src/blend.ts    readHeader     unrelated: it reads text, it does not mix numbers
```

Run (from the Otter folder):

```sh
$(tools/agent_hooks/otter-build.sh) similar examples/similar/repoA examples/similar/repoB examples/similar/repoC --min-lines:8 --across
```

What to expect: one cluster of the four blend routines, spanning three repos, with a
shape distance near 0 (they are built alike) and a words distance that tells how much
of their naming agrees. `readHeader` is in no cluster.
