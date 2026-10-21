# 立方世界 无头冒烟：编译后在 UiDriver 下跑几帧再退出。
#
# 判据：exe 编译得过、帧循环不崩、VOXEL 冒烟标记能让程序跑满若干帧
# 自行退出（顺带验证资源查找路径通不通）。GUI 游戏没有断言式用例套件，
# 这里以"进程按脚本正常退出 + 输出冒烟标记"为通过条件。
#
# 存档另跑两遍：第一遍写盘，第二遍（新进程）必须读回上一遍写的档。
param(
    [string]$Compiler = $env:ZANC,
    [string]$PackageProject = '',
    [int]$TimeoutSeconds = 90
)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$repo = Split-Path -Parent $project
if (-not $Compiler) {
    $local = if ($env:ZAN_HOME) { Join-Path $env:ZAN_HOME 'build/zanc.exe' } else { '' }
    if ($local -and (Test-Path $local)) { $Compiler = $local } else { $Compiler = (Get-Command zanc -ErrorAction Stop).Source }
}
if (-not $PackageProject) { if ($env:ZAN_HOME) { $PackageProject = $env:ZAN_HOME } else { throw '需要 $env:ZAN_HOME 指向 zan-lang 仓库（公共包在它的 packages/ 下）' } }
$out = Join-Path $repo 'build/voxel'
& (Join-Path $PSScriptRoot 'build.ps1') -Compiler $Compiler -PackageProject $PackageProject -Output $out
$exe = Join-Path $out 'Voxel.exe'
if (-not (Test-Path $exe)) { throw "缺少可执行文件：$exe" }
# 存档落在临时目录里，不碰玩家机器上的 %LOCALAPPDATA%/Voxel。
$saveDir = Join-Path $out 'savetest'
if (Test-Path $saveDir) { Remove-Item $saveDir -Recurse -Force }
New-Item -ItemType Directory -Force $saveDir | Out-Null
$env:VOXEL_SAVE = $saveDir
# 冒烟标记：跑满 N 帧后程序自行退出（不走 UiDriver 脚本，避免桌面事件污染）
$env:VOXEL_SMOKE = '1'
$env:VOXEL_FRAMES = '90'
$log = Join-Path $out 'voxel_smoke.log'
if (Test-Path $log) { Remove-Item $log -Force }
$proc = Start-Process -FilePath $exe -WorkingDirectory $out -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $log -RedirectStandardError (Join-Path $out 'voxel_smoke.err')
if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    $proc.Kill()
    throw "无头冒烟超时：应用没在 $TimeoutSeconds 秒内退出"
}
if ($proc.ExitCode -ne 0) { throw "无头冒烟失败：exit=$($proc.ExitCode)" }
if (-not (Select-String -Path $log -Pattern 'VOXEL_SMOKE_OK' -Quiet)) {
    throw "无头冒烟未收尾（缺 VOXEL_SMOKE_OK）：$log"
}
# 存档落盘 + 读回：第二遍是新进程，必须读回第一遍写的档（局数 1 -> 2）。
$saveLine = Select-String -Path $log -Pattern 'VOXEL_SAVE' | Select-Object -First 1
if (-not $saveLine) { throw "没有存档输出行（VOXEL_SAVE）：$log" }
if ($saveLine.Line -notmatch 'runs=1') {
    throw "第一遍存档没写成局数 1：$($saveLine.Line)"
}
if (-not (Test-Path (Join-Path $saveDir 'voxel_slot0.json'))) {
    throw "存档文件没落盘：$saveDir"
}
$log2 = Join-Path $out 'voxel_smoke2.log'
if (Test-Path $log2) { Remove-Item $log2 -Force }
$proc2 = Start-Process -FilePath $exe -WorkingDirectory $out -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $log2 -RedirectStandardError (Join-Path $out 'voxel_smoke2.err')
if (-not $proc2.WaitForExit($TimeoutSeconds * 1000)) {
    $proc2.Kill()
    throw "第二遍无头冒烟超时"
}
$saveLine2 = Select-String -Path $log2 -Pattern 'VOXEL_SAVE' | Select-Object -First 1
if (-not $saveLine2 -or $saveLine2.Line -notmatch 'runs=2') {
    throw "第二遍没读回上一遍的存档（期望 runs=2）：$($saveLine2.Line)"
}
Write-Host "voxel_SAVE_OK runs=1 -> runs=2"
Write-Host "voxel_SMOKE_OK"
