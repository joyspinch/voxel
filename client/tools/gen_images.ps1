# 立方世界 · VOXEL —— AI 原图生成（4 张）。
#
# 生成的 1024² 原图落在 build/raw/（.gitignore 已忽略），**不入库**；
# 随后由 client/tools/make_assets.py 抠黑底、裁边、缩放到显示尺寸 2 倍再入库。
#
# 需要 OPENAI_API_KEY（由 D:\project\secrets.local.ps1 提供）。
# 单张生成也可以直接调 image2.ps1，提示词见下面 $jobs。
param(
    [string]$Image2Script = "$HOME\.codex\skills\local-image2\scripts\image2.ps1",
    [string]$RawDir = ''
)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$repo = Split-Path -Parent $project
if (-not $RawDir) { $RawDir = Join-Path $repo 'build/raw' }
New-Item -ItemType Directory -Force -Path $RawDir | Out-Null

$jobs = @(
  @{ name = 'player'; prompt = 'pixel art voxel game character sprite, blocky cubic robot miner, front view full body, cyan visor helmet, orange work suit, holding a pickaxe, crisp clean edges, flat colors, centered, isolated on solid pure black background' },
  @{ name = 'title'; prompt = 'ornate fantasy game title banner plaque, carved stone frame with golden rivets, empty dark center panel, wide horizontal shape, flat front view, centered, isolated on solid pure black background' },
  @{ name = 'bg_sky'; prompt = 'wide pixel art voxel landscape backdrop, gradient blue sky with soft clouds, distant blocky green hills and a few floating blocky islands, flat side-scrolling background, no characters, no text, full bleed' },
  @{ name = 'blueprint'; prompt = 'top-down flat drafting blueprint parchment sheet, aged tan paper with faint cyan grid lines and small technical marks, blank empty center, no text, no hands, isolated on solid pure black background' }
)

foreach ($j in $jobs) {
  $target = Join-Path $RawDir ($j.name + '.png')
  $ok = $false
  for ($try = 1; $try -le 3 -and -not $ok; $try++) {
    Write-Host ("[gen] {0} try {1}" -f $j.name, $try)
    & $Image2Script generate --model gpt-image-2.5 --prompt $j.prompt --size 1024x1024 --quality high --output-format png --out $target --force
    if ($LASTEXITCODE -eq 0 -and (Test-Path $target)) { $ok = $true }
    else { Start-Sleep -Seconds 60 }
  }
  if (-not $ok) { Write-Host ("[gen] FAILED {0}" -f $j.name) }
}
Write-Host '[gen] all done — 接着跑 python client\tools\make_assets.py 入库'
