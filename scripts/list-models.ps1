<#
.SYNOPSIS
  지금 codex에서 쓸 수 있는 구현 모델 목록을 뽑는다.

.DESCRIPTION
  모델 라인업은 수시로 바뀌므로 워크플로우는 모델명을 박아두지 않는다.
  `codex debug models`의 카탈로그(수백 KB JSON)를 사람이 고를 수 있는 몇 줄로 줄이고,
  사용자 codex 설정(config.toml)의 기본 모델·effort를 함께 보여준다.

.EXAMPLE
  pwsh scripts/list-models.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
  throw "codex CLI를 찾을 수 없다. https://developers.openai.com/codex/cli 에서 설치하고 'codex login'을 마쳐라."
}

$raw = (& codex debug models 2>$null) -join "`n"
if ($LASTEXITCODE -ne 0 -or -not $raw) {
  throw "'codex debug models' 실패. 'codex login' 상태를 확인해라."
}
$models = ($raw.Substring($raw.IndexOf('{')) | ConvertFrom-Json).models

# config.toml 최상위의 model / model_reasoning_effort만 본다. 프로필은 무시한다.
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$configPath = Join-Path $codexHome 'config.toml'
$default = @{}
if (Test-Path -LiteralPath $configPath) {
  foreach ($line in @(Get-Content -LiteralPath $configPath -Encoding utf8)) {
    if ($line -match '^\s*\[') { break }
    if ($line -match '^\s*(model|model_reasoning_effort)\s*=\s*"([^"]*)"') { $default[$Matches[1]] = $Matches[2] }
  }
}

$dModel  = if ($default['model']) { $default['model'] } else { '(codex 내장 기본값)' }
$dEffort = if ($default['model_reasoning_effort']) { $default['model_reasoning_effort'] } else { '(모델 기본값)' }
Write-Output "기본값: model=$dModel effort=$dEffort  ($configPath)"
Write-Output ''

# StrictMode에서는 없는 속성을 읽으면 예외가 나므로 PSObject로 꺼낸다.
function Get-Prop($Obj, [string]$Name, $Fallback) {
  $p = $Obj.PSObject.Properties[$Name]
  if ($p -and $null -ne $p.Value) { return $p.Value } else { return $Fallback }
}

$rows = @($models | Where-Object { (Get-Prop $_ 'visibility' '') -eq 'list' } | Sort-Object { Get-Prop $_ 'priority' 999 })
$width = (($rows | ForEach-Object { $_.slug.Length } | Measure-Object -Maximum).Maximum) + 2
foreach ($m in $rows) {
  $mark = if ($m.slug -eq $default['model']) { '*' } else { ' ' }
  $efforts = (@(Get-Prop $m 'supported_reasoning_levels' @()) | ForEach-Object { $_.effort }) -join '|'
  Write-Output ("{0} {1}{2}{3}" -f $mark, $m.slug.PadRight($width), $efforts.PadRight(34), (Get-Prop $m 'description' ''))
}
