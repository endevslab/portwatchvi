# Diagnostic runs for the VIctory fork.
#
# Every switch here lives behind the `diagnostics` feature, so the first
# command builds the `diag` profile (release codegen + diagnostics):
#   powershell -File diagnose.ps1 build
#
# Runs (the title's own files must already be configured in victory.toml):
#   powershell -File diagnose.ps1 timing  <path-to-exe> [out-dir]
#   powershell -File diagnose.ps1 stacks  <path-to-exe> [out-dir]
#   powershell -File diagnose.ps1 loops   <path-to-exe> [out-dir] [limit]
#   powershell -File diagnose.ps1 capture <path-to-exe> [out-dir]
#
# Output (logs and captures) goes under `out-dir`, default
# %TEMP%\victory-diag\<command>-<timestamp>. Nothing is written into the
# repository. Each run also names the game's `crashes.log` on failure.

param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Cmd,
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = "Stop"
# Resolve the caller's paths before changing directory, so a relative exe or
# out-dir means what it meant where the caller ran the script.
if ($Rest.Count -ge 1 -and $Rest[0]) {
    $Rest[0] = (Resolve-Path -LiteralPath $Rest[0] -ErrorAction Stop).ProviderPath
}
if ($Rest.Count -ge 2 -and $Rest[1]) {
    # Windows PowerShell 5.1 runs on .NET Framework, where Path.GetFullPath has
    # only the one-argument overload; resolve a relative root against the
    # caller's directory with Join-Path instead.
    $Rest[1] = if ([System.IO.Path]::IsPathRooted($Rest[1])) {
        $Rest[1]
    }
    else {
        Join-Path $PWD.Path $Rest[1]
    }
}
$Repo = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Repo

function Diag-Exe {
    return (Join-Path $Repo "target\diag\victory.exe")
}

function Invoke-DiagRun {
    param([Parameter(Mandatory = $true)][string]$Log)
    # Windows PowerShell 5.1 turns a native command's stderr into
    # ErrorRecords, and under `Stop` the first one aborts the run before the
    # log is written. The title logs to stderr on a normal start, so relax the
    # preference for this call only and report the exit code ourselves.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & (Diag-Exe) run $Rest[0] --execute 2>&1 | Tee-Object -FilePath $Log
    }
    finally {
        $ErrorActionPreference = $previous
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "run exited with code $LASTEXITCODE (log: $Log)"
    }
    # Tee-Object writes UTF-16 under Windows PowerShell, which grep and the
    # other host tools cannot read; re-save the log as UTF-8.
    if (Test-Path $Log) {
        $raw = Get-Content -Raw -Path $Log
        Set-Content -Path $Log -Value $raw -Encoding UTF8
    }
}

function Out-Dir {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        # The run commands take the output root as their second remaining
        # argument; passing it explicitly keeps the argument contract visible.
        [string]$Root
    )
    $root = if ($Root) { $Root } else { Join-Path $env:TEMP "victory-diag\$Name-$(Get-Date -Format yyyyMMdd-HHmmss)" }
    $dir = New-Item -ItemType Directory -Force -Path $root | Select-Object -ExpandProperty FullName
    return $dir
}

switch ($Cmd) {
    "build" {
        cargo build --profile diag -p victory --features diagnostics
        # A native non-zero exit does not trip $ErrorActionPreference here, so
        # a failed build would otherwise report success.
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        break
    }
    "timing" {
        # Each submission list is timed on its own; slow lists are logged with
        # their slowest commands (needs VICTORY_D3D12_DRED for the command
        # names). Note: setting VICTORY_GPU_TIMING disables the late-wait and
        # relay speed switches, so this measures the clean baseline.
        if ($Rest.Count -lt 1) { throw "timing needs the title's exe path" }
        $env:VICTORY_GPU_TIMING = "1"
        $env:VICTORY_D3D12_DRED = "1"
        $env:VICTORY_LOG = "victory_gpu=debug,victory_loader=info"
        $out = Out-Dir "timing" -Root $Rest[1]
        Invoke-DiagRun -Log (Join-Path $out "timing.log")
        break
    }
    "stacks" {
        # Every thread's stack, unwound to module+rva, at the listed seconds:
        # shows what the CPU waits on when the frame is slow.
        if ($Rest.Count -lt 1) { throw "stacks needs the title's exe path" }
        $env:VICTORY_STACKS = "30,60,90"
        $out = Out-Dir "stacks" -Root $Rest[1]
        Invoke-DiagRun -Log (Join-Path $out "stacks.log")
        break
    }
    "loops" {
        # Translated loops stop after `limit` iterations instead of 2^20. If a
        # low limit makes frames much faster, loops hitting the limit are the
        # cost (own shader-cache entries, so it changes nothing else).
        if ($Rest.Count -lt 1) { throw "loops needs the title's exe path" }
        $limit = if ($Rest.Count -ge 3) { $Rest[2] } else { "1024" }
        $env:VICTORY_SHADER_LOOP_LIMIT = $limit
        $out = Out-Dir "loops-$limit" -Root $Rest[1]
        Invoke-DiagRun -Log (Join-Path $out "loops.log")
        break
    }
    "capture" {
        # Frames as PNG (power-of-two frames, plus the world's 2nd/6th/30th/80th
        # after the first 500-draw frame), per-draw ops files, and every listed
        # frame's render targets dumped with value logs (depth, stencil, packed
        # light). This is the tool for the black shadows and the empty interior.
        if ($Rest.Count -lt 1) { throw "capture needs the title's exe path" }
        $out = Out-Dir "capture" -Root $Rest[1]
        $frames = Join-Path $out "frames"
        New-Item -ItemType Directory -Force -Path $frames | Out-Null
        $env:VICTORY_CAPTURE = $frames
        $env:VICTORY_CAPTURE_WORLD = "1"
        $env:VICTORY_DUMP_TARGETS = "1"
        Invoke-DiagRun -Log (Join-Path $out "capture.log")
        break
    }
    default {
        Write-Host "unknown command: $Cmd (build | timing | stacks | loops | capture)"
        exit 1
    }
}
