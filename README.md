# endevslab's VIctory fork

A work-in-progress fork of [VIctory](https://github.com/Marvisak/VIctory) by Marvisak — a
compatibility layer that runs an Xbox Series title natively on Windows from files the user
supplies. It follows upstream `main` and carries the fixes of
[hyphennn's victory-fork](https://github.com/fxceless/victory-fork) (upstream's own README
and history are there, not repeated here), plus the work recorded in
[`odd/tasks/fluid-world-frames.md`](odd/tasks/fluid-world-frames.md).

**This repository contains no game files, code or assets.** You need your own copy of the
game. It is not affiliated with or endorsed by the game's developer or publisher.

GPL-3.0-or-later, like VIctory.

## Status, measured 2026-11-25

Tested on one PC: Windows 11, Intel i7-14700KF, NVIDIA RTX 4070 12 GB, 32 GB RAM. The
Series X profile is used throughout. Every number below was read from the layer's own
instrumentation in a run of this repository's `diag` build; the runs and the method are in
[`odd/tasks/fluid-world-frames.md`](odd/tasks/fluid-world-frames.md).

| Stage | State |
|-------|-------|
| Boot, first-boot screens, profile selector, start screen | works, 30 fps |
| Saves | the game autosaves a checkpoint and loads it again |
| Loading into the world | about 50 s, then the title enters its 3D attract sequence by itself |
| First gameplay scene (the prologue) | renders: characters, textures, sky, sunlit exterior; HUD, pause menu and pad input work |
| Light in shadow | **missing**: the title's ray-traced bounce light and ray-traced lamp and sun shadows do not run yet, so anything the sun does not hit directly is black |
| Frame rate in the world | **2-3 fps**, 455-555 ms per frame |
| Stability | no driver hang or device loss in runs of 240-300 s; the title's own attract loop returns to the menu by itself |

### Where the world's frame goes

`on the GPU` is 240-320 ms with the card 79-80% busy, and the host side is serialized
against it:

| Bucket | Per frame |
|--------|-----------|
| `on the GPU` (our commands) | 240-320 ms, card 79-80% busy |
| `copying back` (host, relay thread) | 300-390 ms over 68-71 MB |
| `preparing` (host) | 170-210 ms |
| `heap buffers` pass | 20-200 ms |

The single largest host stall is one wait, reported by the layer as
`title memory read`: **281 ms per frame**, in `crates/victory-gpu/src/host.rs:3984`. It is a
real read-after-write: the next frame's uploads touch memory the previous frame's shaders
declared, so the submission waits for that frame to land. Removing the wait alone makes the
frame *worse* (measured: 1090-1355 ms), because the wait is where the host's work overlaps
the card; the fix is to stop that upload from reading title memory at all
(`crates/victory-gpu/src/draw.rs:463`, where an unaligned root view is filled from title
memory instead of from the card's copy).

### Ray tracing

Nothing is lit by ray tracing yet. The machinery is built and unit-tested and it is off by
default; see [`docs/fork-ray-tracing.md`](docs/fork-ray-tracing.md) for what translates, how
the console's node test is emulated in DXIL, and the gaps that keep the builder from running
(a few of its pipelines ask for 64-lane waves on a 32-lane GPU, and five shadow-mask trace
programs do not translate).

## Speed work in this fork

Each of these was accepted only after an A/B run of the same driver on the same scene.

- Texture refresh no longer waits on the title-memory mapping lock: 2780 → 1402 ms per
  frame at the time, the `textures` bucket 1188 → 16 ms.
- Host copies of title buffers and of the textures the title fills are let go when nothing
  names them, with byte budgets (`VICTORY_BUFFER_COPIES_MB`, `VICTORY_TEXTURE_COPIES_MB`,
  both 1024): the world's streaming was leaving 4,255 buffer copies (4.3 GB) and 9,955
  texture copies (1.6 GB) alive three minutes in.
- Results of past frames are landed by a relay thread beside the submitting one
  (`VICTORY_RELAY`), and submissions can be sent ahead of the wait for the card
  (`VICTORY_LATE_WAIT`).
- Waits for memory values, write-watch and page queries no longer walk page tables per call.
- Translated shaders get clean-up passes over the finished module (about 43 % fewer host
  instructions, worth about 20 ms of GPU time per frame on the test machine;
  `VICTORY_SHADER_OPT=0` turns them off).
- Meshlet culling read its scene buffers as the wrong kind of view, per-draw descriptor
  tables could run out, light was read back through empty copies, and several material
  programs did not translate: all fixed.

### Measured and rejected

Recorded so nobody repeats them: `VICTORY_WIDE_MERGE=1`, `VICTORY_CARD_REHASH_RUNS=1`,
`VICTORY_CARD_BUFFERS_MIN_MB=1`, `VICTORY_LATE_WAIT=2` and `VICTORY_LATE_WAIT_WRITES=0` do not
move the world's frame time. They move the host's stall from one place to another (for
example `LATE_WAIT_WRITES=0` takes `copying back` from 338 ms to 80 ms and puts 362 ms back as
`bottom-of-pipe writes`). `VICTORY_JOIN_COPIES=1` has nothing to join: no title buffer copy
continues the one before it.

Measured with `VICTORY_GPU_TIMING=1` is **not** a valid measurement of behaviour: that switch
turns the relay and the late present off, and the same scene costs 1399 ms per frame instead
of 501 ms. It names buckets; it does not accept or reject a change.

## Requirements

Windows 10/11 x64, a CPU with AVX2, a Direct3D 12 GPU with shader model 6.6 (and mesh shaders
for the world), Rust (pinned in `rust-toolchain.toml`). Several GiB of Windows commit are
needed at startup: check **Committed** in Task Manager, and if `crashes.log` reports Windows
error 1455, close other applications or raise the paging file. About 22 GB of memory is in
use during play.

## Running it

```powershell
cargo xtask install-hooks                # asset-policy check on every commit
copy victory.example.toml victory.toml   # then set your paths (outside the repo)
cargo test --workspace                   # needs no game data
cargo run -p victory -- config           # check your paths

cargo build --release -p victory
target\release\victory.exe run <game dir>\<the title's exe> --execute
```

The window caption shows the frame rate. Saves, settings and `crashes.log` live under the
data folder (default `%LOCALAPPDATA%\victory\data`); derived data under the cache folder.

Input: XInput pads, or the keyboard as a pad while the title's window has focus —
W A S D / I J K L sticks, arrows D-pad, Enter/Backspace/X/Y A/B/X/Y, Q/E and Z/C shoulders
and triggers, F/H stick clicks, Esc/Tab Menu/View.

## Commands

```
victory inspect <exe|dll> [--imports] [--exports]
victory census [paths...] [--missing] [--strict]
victory lib-exports <import.lib> [--list]
victory shader-info [paths...] [--verbose] [--disasm]
victory translate [paths...] [--validate] [--pipelines] [--list] [--jobs N]
victory run <exe> [--execute] [--unimplemented trap|zero] [--strict]
            [--console series-x|series-s] [-- <title arguments>]
victory config
```

Logging: `VICTORY_LOG=victory_loader=trace,info` (a release build logs info and above).

## Debugging

A release build has no debugging aids. Build them in with

```powershell
cargo build --profile diag -p victory --features diagnostics   # target\diag\victory.exe
```

The `diagnostics` **feature** is what brings the switches in; `--profile diag` alone does not.

| Variable | Effect |
|----------|--------|
| `VICTORY_LOG=<target>=debug,...` | debug and trace output |
| `VICTORY_STACKS=20,60` | every thread's stack at those seconds |
| `VICTORY_WATCH=<rva>,...` | logs a title u32 when it changes |
| `VICTORY_KEYS=30:Enter,35:X` | presses keys at those seconds, focus or not |
| `VICTORY_CRASH_SAVE=<rva>:<len>,...` | saves title memory to the cache folder on a crash |
| `VICTORY_CAPTURE=<dir>` | saves presented frames (powers of two, or `VICTORY_CAPTURE_FRAMES=<list>`) |
| `VICTORY_DUMP_TARGETS=1` | with the two above, saves every render target of those frames |
| `VICTORY_D3D12_DEBUG=1` | host debug layer |
| `VICTORY_D3D12_GBV=1` | with the above, GPU-based validation (slow) |
| `VICTORY_D3D12_DRED=1` | on a GPU failure, the allocation hit and the commands in flight |
| `VICTORY_PIPELINE_WAIT_MS=24` | reduce the per-frame wait for background pipeline creation from 500 ms |
| `VICTORY_SKIP_PIPELINES=<hash>,...` | omit draws and dispatches whose pipeline contains a listed shader hash |
| `VICTORY_TEXTURE_WAIT=1` | texture refreshes wait for the runtime to finish remapping title memory |
| `VICTORY_GPU_TIMING=1` | run and time each list of a submission on its own (see the warning above) |
| `VICTORY_D3D12_WARP=1` | host device on the software adapter (slow) |
| `VICTORY_SHADER_LOOP_LIMIT=<n>` | translated shader loops stop after `n` iterations per lane instead of 2^20 |
| `VICTORY_AUDIO_CAPTURE=<file.wav>` | records what the title plays |
| `VICTORY_XMA_DUMP=<dir>` | saves the first 32 XMA voices' context and input |

Speed switches, all described where they are read: `VICTORY_LATE_WAIT` (1-3),
`VICTORY_RELAY` (1-2), `VICTORY_WIDE_BACK`, `VICTORY_WIDE_MERGE`, `VICTORY_CARD_REHASH_RUNS`,
`VICTORY_JOIN_COPIES`, `VICTORY_CARD_BUFFERS_MIN_MB`, `VICTORY_CARD_BUFFERS_MB`,
`VICTORY_BUFFER_COPIES_MB`, `VICTORY_TEXTURE_COPIES_MB`, `VICTORY_SHADER_OPT`,
`VICTORY_INPLACE`, `VICTORY_BVH_BUILDER`, `VICTORY_BVH_QUARANTINE`, `VICTORY_WAVE_WIDE`.

## Known problems

- Everything in shadow is black: the ray-traced light and shadows do not run yet.
- The interior of the first gameplay room is sometimes not drawn after the cutscene hands
  over to gameplay.
- Around 22 GB of memory is in use during play.
- Many changes here are specific to this title and this GPU, and some are marked
  `shortcut:` in the code where they approximate what the console does.

## Credit

[VIctory](https://github.com/Marvisak/VIctory) by Marvisak and its contributors is the base of
all of this (GPL-3.0-or-later); its README, architecture notes and status live in that
repository. [XCL](https://github.com/ivall/xcl) by ivall and its contributors (GPL-2.0-only)
was a reference for how the same title behaves under another layer; fixes inspired by it were
written anew here. See [`docs/architecture.md`](docs/architecture.md) for how this layer is
built and [`docs/asset-policy.md`](docs/asset-policy.md) for why the repository is text-only.
