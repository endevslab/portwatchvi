# fluid-world-frames

Make the title's world frame time acceptable: remove the host-side stalls measured in the world (2780 ms/frame, 0.4 fps) without changing what the title renders.

## Specs

S1. The user's requirement, verbatim: "procede ya que debe funcionar fluido el juego a todos los fps posibles has todo lo necesario para que corra bien".

S2. Baseline to beat, measured in the world with the `diag` build and the same driver used for verification (`VICTORY_GPU_TIMING=1`, `VICTORY_D3D12_DRED=1`): 2780 ms/frame average, `textures` bucket 1188 ms of which 964 ms is the `MAPPING` lock wait, "the title had not submitted" 553 ms, `copying back` 212 ms, heap-buffer pass 253 ms, `on the GPU` 218 ms. Every accepted change is proven by an A/B run of that same driver: ms/frame must go down and the visual output must not regress.

S3. The GPU is not the target: per-command GPU timings are 0.7-1.25 ms/frame and the card reads 2-10% busy. Work that only moves cost between CPU buckets, or that removes GPU work by dropping draws, does not satisfy S1.

S4. A shader or pipeline that cannot be translated is out of scope for frame time; the 745-4067 permanently dropped draws per report window remove GPU work and must not be "fixed" by dropping more.

## Tasks

- T1 (S1, S2) — Make the texture refresh never block on the title-memory mapping lock. Route: inline evidence already gathered; writer for the code. Commit: `6be8cb6`. Tests: 112 pass, 3 consecutive runs; the new cases take turns on a module mutex because the mapping lock is process-wide.
- T2 (S1, S2) — Commit the `diagnose.ps1` runner repairs (stderr no longer aborts the run, UTF-8 logs) plus the review advisories that hold: `$LASTEXITCODE` checks, explicit out-dir argument, non-zero exit on an unknown command. Route: inline. Commit: `7b94d9e` (task file), `447471f` (runner), `3063786` (correction: relative out-dir without the two-argument `GetFullPath`, which does not exist on .NET Framework). Reviewed: lineage `review-11de453f5221c103`, approved.
- T3 (S1, S2) — Name the remaining title-side gap: symbolize the hot RVAs (`victory.exe+0x5fb511`, `0x614c23`, `0x5fb713`, `0x1247c2`, `0xe6769`, `0xd5a24`) against `target/diag/victory.pdb`, then attack what the symbol shows ("the title had not submitted" = 900 ms/frame). Route: parent + writer. Commit: work unit 3.
- T4 (S1, S2) — Reduce the remaining host-side buckets (heap-buffer texture pass 253 ms, `copying back` 82-212 ms) guided by the same meters. Route: writer. Commit: work unit 4.
- T5 (S1-S4) — Verify end to end: A/B driver runs in the world, report ms/frame, fps, and that the frame image did not regress. Route: parent. No commit.

## Log

L1 (verbatim): "procede ya que debe funcionar fluido el juego a todos los fps posibles has todo lo necesario para que corra bien"

L2 (evidence, previous probe): the title renders the menu at 30 fps / 33 ms with the GPU idle; entering the world explodes to 448-8297 draws/frame and 1.1-12 s per frame. The window title is a live meter (`fps / ms per frame / draws per frame`).

L3 (evidence, diagnosis): `VICTORY_TEXTURE_NO_WAIT=1` A/B — ms/frame 2780 -> 1635, textures 1188 -> 16 ms, refresh "waiting for title memory to hold still" 964 -> 0 ms, cpu user per 5 s window 16674 -> 2142 ms. The lock is held by `Staging::refresh` across the write-watch query, a whole-texture blake3 and the detile (crates/victory-gpu/src/texture.rs:667-741) while the runtime takes it alone to remap.

L4 (evidence, after the A/B): the residual frame is "the title had not submitted" 900 ms/frame with our own thread working 217 ms, so the next target is title-side time, not host preparation. The main thread parks in `WaitForSingleObject` from `victory.exe+0x5fb511` in both runs.

L5 (review of the runner unit): the refuter found one introduced BLOCKER, R3-001 — the two-argument `Path.GetFullPath` does not exist on .NET Framework. Reproduced on this host (`MethodException: no overload with 2 arguments`) and corrected in `3063786`. Non-blocking advisories that stay open as follow-ups: `Out-Dir`'s `$Root` parameter and local `$root` are one case-insensitive variable (R2-case-insensitive-root); `Invoke-DiagRun` reads the script-scope `$Rest[0]` instead of taking the exe path as a parameter (R2-implicit-rest); the helper only prints `$LASTEXITCODE` and the script still exits 0 after a failed title run (R2-masked-exit).

L6 (A/B, card-side shadow comparison): `VICTORY_CARD_BUFFERS_MIN_MB=1` is not a win — ms/frame 1635 -> 2871 with the same fps, the CPU comparison only drops 404.8 -> 360.9 MB/frame, cpu user 2142 -> 1241 ms but kernel 983 -> 1160 ms. Discarded as the next lever.

L7 (slice boundary): work units on `perf/fluid-world-frames` are `7b94d9e` (task file), `447471f` + `3063786` (runner, reviewed), `6be8cb6` (texture refresh). Delivery shape (one PR or chained) is a separate decision at publish time.

L8 (review of the texture/lock/copy unit): approved, lineage `review-297b78f6690118a9`. The reliability lens first died twice on a provider generation failure (44k and 46k reasoning tokens, no verdict); after the reviewer output ceiling was raised it produced the verdict. Open advisories: R3-001 `Invoke-DiagRun` prints but does not propagate `$LASTEXITCODE`; R3-002 a copy is treated as gone from one failed kernel byte read, which can also fail while the runtime is remapping; R3-003 the over-budget eviction branch had no test.

L9 (memory ledger, three-minute run): our attributed side totals ~10.2 GB in both runs and the residual ~8 GB is never attributed by any log line (likely the title's own commit and driver heaps). Pools that grow: `host textures` 7 -> 10921 alive (4504 MB), copies the title fills 1 -> 9955 alive (1592 MB), `shapes of placed views kept` 477 -> 55440. The first sweep let go of twice as many windows (635 / 2924 MB vs 304 / 1424 MB) but the run still ended at the same private memory, so the sweep alone was not the fix.

L10 (slice boundary): the branch is now past the review slice. Slices: `7b94d9e`+`447471f`+`3063786` (runner), `6be8cb6` (texture lock), `6ce1c87`+`e240794` (buffer-copy sweep), `3b0b36c` (placed-texture pools). Each work unit was reviewed or is pending review; the delivery shape (one PR or chained) stays a decision at publish time.
