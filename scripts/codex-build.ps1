<#
.SYNOPSIS
  PLAN.md를 codex-luna-max에게 넘겨 구현시키고, 결과 diff를 검수용으로 캡처한다.

.DESCRIPTION
  claude-codex 워크플로우의 2단계(구현)를 실행한다.
  RunDir에 PLAN.md와 BUILD_PROMPT.md가 있어야 하며, 실행 후 다음을 남긴다:

    STATUS            running | done | failed:<exit code>
    BUILD.log         codex 전체 출력
    BUILD_SUMMARY.md  codex의 마지막 메시지 (구현 보고)
    DIFF.patch        구현 전후 diff (.pnb 제외)
    CHANGED.txt       변경된 파일 목록
    BASE_HEAD.txt     구현 시작 시점의 커밋 SHA

.EXAMPLE
  pwsh scripts/codex-build.ps1 -RunDir .pnb/runs/001-add-login

.EXAMPLE
  # 검수 지적사항을 같은 codex 세션에 이어서 반영
  pwsh scripts/codex-build.ps1 -RunDir .pnb/runs/001-add-login -Resume -PromptFile .pnb/runs/001-add-login/FIX_PROMPT.md
#>
[CmdletBinding()]
param(
  # 실행 산출물이 모이는 디렉터리. PLAN.md / BUILD_PROMPT.md가 여기 있어야 한다.
  [Parameter(Mandatory = $true)]
  [string]$RunDir,

  # codex가 작업할 저장소 루트. 기본값은 현재 디렉터리.
  [string]$RepoRoot = (Get-Location).Path,

  # 구현 모델. codex-luna-max = gpt-5.6-luna + max reasoning.
  [string]$Model = 'gpt-5.6-luna',

  # 리즈닝 강도: low | medium | high | xhigh | max
  [string]$Effort = 'max',

  # 샌드박스: read-only | workspace-write | danger-full-access
  [string]$Sandbox = 'workspace-write',

  # codex에게 줄 지시문 파일. 기본값은 <RunDir>/BUILD_PROMPT.md
  [string]$PromptFile,

  # 직전 codex 세션을 이어서 실행 (검수 지적사항 반영용)
  [switch]$Resume
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 한글 프롬프트/로그가 깨지지 않도록 UTF-8 고정
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$env:PYTHONIOENCODING = 'utf-8'

function Write-Utf8([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

# ---------------------------------------------------------------- 사전 확인
$codex = Get-Command codex -ErrorAction SilentlyContinue
if (-not $codex) {
  throw "codex CLI를 찾을 수 없다. https://developers.openai.com/codex/cli 에서 설치하고 'codex login'을 마쳐라."
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if (-not (Test-Path -LiteralPath $RunDir)) {
  throw "RunDir이 없다: $RunDir"
}
$RunDir = (Resolve-Path -LiteralPath $RunDir).Path

$planPath = Join-Path $RunDir 'PLAN.md'
if (-not (Test-Path -LiteralPath $planPath)) {
  throw "PLAN.md가 없다: $planPath — 기획 단계를 먼저 끝내라."
}

if (-not $PromptFile) { $PromptFile = Join-Path $RunDir 'BUILD_PROMPT.md' }
if (-not (Test-Path -LiteralPath $PromptFile)) {
  throw "지시문 파일이 없다: $PromptFile"
}
$PromptFile = (Resolve-Path -LiteralPath $PromptFile).Path

$statusPath  = Join-Path $RunDir 'STATUS'
$logPath     = Join-Path $RunDir 'BUILD.log'
$summaryPath = Join-Path $RunDir 'BUILD_SUMMARY.md'
$diffPath    = Join-Path $RunDir 'DIFF.patch'
$changedPath = Join-Path $RunDir 'CHANGED.txt'
$baseHeadPath = Join-Path $RunDir 'BASE_HEAD.txt'
$baseUntrackedPath = Join-Path $RunDir 'BASE_UNTRACKED.txt'

# ------------------------------------------------------------- 기준점 기록
$isGitRepo = $false
Push-Location $RepoRoot
try {
  $null = git rev-parse --is-inside-work-tree 2>$null
  $isGitRepo = ($LASTEXITCODE -eq 0)
  if ($isGitRepo -and -not $Resume) {
    $head = (git rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) { $head = '(no commits yet)' }
    Write-Utf8 $baseHeadPath "$head`n"

    # 빌드 전부터 워킹 트리에 있던 untracked 파일을 내용 해시와 함께 기록한다.
    # 이걸 안 하면 커밋 안 된 기존 파일이 전부 "구현자가 새로 만든 파일"로 diff에 잡혀
    # 검수자가 엉뚱한 범위 이탈을 보고하게 된다.
    $baseLines = @()
    foreach ($f in @(git ls-files --others --exclude-standard -- . ':(exclude).pnb' 2>$null)) {
      if ([string]::IsNullOrWhiteSpace($f)) { continue }
      $h = (git hash-object -- "$f" 2>$null)
      if ($LASTEXITCODE -eq 0 -and $h) { $baseLines += "$h`t$f" }
    }
    Write-Utf8 $baseUntrackedPath (($baseLines -join "`n") + "`n")
  }
} finally {
  Pop-Location
}

Write-Utf8 $statusPath "running`n"

# ------------------------------------------------------------------ 실행
# 프롬프트 본문은 파일로 넘긴다. 인자에 한글 장문을 실으면 셸 인코딩/길이 문제가 생긴다.
$prompt = "Read the file at $PromptFile and follow it exactly. It is your complete task brief."

# `codex exec resume`는 -s/-C를 받지 않는다. 그쪽은 -c 설정과 프로세스 cwd로 대신한다.
if ($Resume) {
  $codexArgs = @(
    'exec', 'resume', '--last',
    '-m', $Model,
    '-c', "model_reasoning_effort=$Effort",
    '-c', "sandbox_mode=$Sandbox",
    '-o', $summaryPath,
    $prompt
  )
} else {
  $codexArgs = @(
    'exec',
    '-m', $Model,
    '-c', "model_reasoning_effort=$Effort",
    '-s', $Sandbox,
    '-C', $RepoRoot,
    '-o', $summaryPath,
    $prompt
  )
}

Write-Host "[codex-build] model=$Model effort=$Effort sandbox=$Sandbox"
Write-Host "[codex-build] repo=$RepoRoot"
Write-Host "[codex-build] brief=$PromptFile"
Write-Host ''

$exitCode = 0
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
Push-Location $RepoRoot   # resume 모드는 -C를 못 받으므로 cwd로 작업 위치를 정한다
try {
  if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
  }
  & codex @codexArgs 2>&1 | Tee-Object -FilePath $logPath
  $exitCode = $LASTEXITCODE
} finally {
  Pop-Location
  $ErrorActionPreference = $prevEap
}

# ------------------------------------------------------------- 결과 캡처
if ($isGitRepo) {
  Push-Location $RepoRoot
  try {
    # 실제 인덱스를 건드리지 않도록 임시 인덱스에서 diff를 만든다.
    # 신규 파일도 patch에 포함되고, 워크플로우 산출물(.pnb)은 제외한다.
    $tmpIndex = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-build-index-" + [guid]::NewGuid().ToString('N'))
    $env:GIT_INDEX_FILE = $tmpIndex
    try {
      $null = git read-tree HEAD 2>$null
      $null = git add -A -- . ':(exclude).pnb' 2>$null

      # 빌드 전부터 있던 untracked 파일 중 내용이 그대로인 것은 임시 인덱스에서 뺀다.
      # 내용이 바뀐 것은 남겨둔다 — 그건 구현자가 손댄 진짜 변경이다.
      if (Test-Path -LiteralPath $baseUntrackedPath) {
        foreach ($line in @(Get-Content -LiteralPath $baseUntrackedPath)) {
          if ($line -notmatch "`t") { continue }
          $parts = $line -split "`t", 2
          $oldHash = $parts[0]; $relPath = $parts[1]
          if (-not (Test-Path -LiteralPath $relPath)) { continue }
          $newHash = (git hash-object -- "$relPath" 2>$null)
          if ($newHash -eq $oldHash) { $null = git rm --cached --quiet --force -- "$relPath" 2>$null }
        }
      }

      git diff --cached HEAD -- . ':(exclude).pnb' 2>$null | Set-Content -LiteralPath $diffPath -Encoding utf8
      git diff --cached --name-status HEAD -- . ':(exclude).pnb' 2>$null | Set-Content -LiteralPath $changedPath -Encoding utf8
    } finally {
      Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath $tmpIndex -Force -ErrorAction SilentlyContinue
    }
  } finally {
    Pop-Location
  }
} else {
  Write-Utf8 $diffPath "(git 저장소가 아니라 diff를 캡처하지 못했다)`n"
  Write-Utf8 $changedPath "(git 저장소가 아님)`n"
}

if ($exitCode -eq 0) {
  Write-Utf8 $statusPath "done`n"
  $changed = 0
  if (Test-Path -LiteralPath $changedPath) {
    $changed = @(Get-Content -LiteralPath $changedPath | Where-Object { $_.Trim() -ne '' }).Count
  }
  Write-Host ''
  Write-Host "[codex-build] 완료. 변경 파일 ${changed}개."
  Write-Host "[codex-build] 산출물: $RunDir"
} else {
  Write-Utf8 $statusPath "failed:$exitCode`n"
  Write-Host ''
  Write-Host "[codex-build] 실패 (exit $exitCode). 로그: $logPath"
}

exit $exitCode
