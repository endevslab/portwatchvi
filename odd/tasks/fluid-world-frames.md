# fluid-world-frames

Make the title's world frame time acceptable: remove the host-side stalls measured in the world (2780 ms/frame, 0.4 fps) without changing what the title renders.

## Specs

S1. The user's requirement, verbatim: "procede ya que debe funcionar fluido el juego a todos los fps posibles has todo lo necesario para que corra bien".

S2. Baseline to beat, measured in the world with the `diag` build and the same driver used for verification (`VICTORY_GPU_TIMING=1`, `VICTORY_D3D12_DRED=1`): 2780 ms/frame average, `textures` bucket 1188 ms of which 964 ms is the `MAPPING` lock wait, "the title had not submitted" 553 ms, `copying back` 212 ms, heap-buffer pass 253 ms, `on the GPU` 218 ms. Every accepted change is proven by an A/B run of that same driver: ms/frame must go down and the visual output must not regress.

S3. The GPU is not the target: per-command GPU timings are 0.7-1.25 ms/frame and the card reads 2-10% busy. Work that only moves cost between CPU buckets, or that removes GPU work by dropping draws, does not satisfy S1.

S4. A shader or pipeline that cannot be translated is out of scope for frame time; the 745-4067 permanently dropped draws per report window remove GPU work and must not be "fixed" by dropping more.

## Tasks

- T1 (S1, S2) — Make the texture refresh never block on the title-memory mapping lock. Route: inline evidence already gathered; writer for the code. Commit: work unit 1.
- T2 (S1, S2) — Commit the `diagnose.ps1` runner repairs (stderr no longer aborts the run, UTF-8 logs) plus the review advisories that hold: `$LASTEXITCODE` checks, explicit out-dir argument, non-zero exit on an unknown command. Route: inline. Commit: work unit 0.
- T3 (S1, S2) — Name the remaining title-side gap: symbolize the hot RVAs (`victory.exe+0x5fb511`, `0x614c23`, `0x5fb713`, `0x1247c2`, `0xe6769`, `0xd5a24`) against `target/diag/victory.pdb`, then attack what the symbol shows ("the title had not submitted" = 900 ms/frame). Route: parent + writer. Commit: work unit 3.
- T4 (S1, S2) — Reduce the remaining host-side buckets (heap-buffer texture pass 253 ms, `copying back` 82-212 ms) guided by the same meters. Route: writer. Commit: work unit 4.
- T5 (S1-S4) — Verify end to end: A/B driver runs in the world, report ms/frame, fps, and that the frame image did not regress. Route: parent. No commit.

## Log

L1 (verbatim): "procede ya que debe funcionar fluido el juego a todos los fps posibles has todo lo necesario para que corra bien"

L2 (evidence, previous probe): the title renders the menu at 30 fps / 33 ms with the GPU idle; entering the world explodes to 448-8297 draws/frame and 1.1-12 s per frame. The window title is a live meter (`fps / ms per frame / draws per frame`).

L3 (evidence, diagnosis): `VICTORY_TEXTURE_NO_WAIT=1` A/B — ms/frame 2780 -> 1635, textures 1188 -> 16 ms, refresh "waiting for title memory to hold still" 964 -> 0 ms, cpu user per 5 s window 16674 -> 2142 ms. The lock is held by `Staging::refresh` across the write-watch query, a whole-texture blake3 and the detile (crates/victory-gpu/src/texture.rs:667-741) while the runtime takes it alone to remap.

L4 (evidence, after the A/B): the residual frame is "the title had not submitted" 900 ms/frame with our own thread working 217 ms, so the next target is title-side time, not host preparation. The main thread parks in `WaitForSingleObject` from `victory.exe+0x5fb511` in both runs.
