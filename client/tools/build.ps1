# 立方世界 构建：编译 client/src/ 下全部 .zan → 可执行文件。
#
# 公共包（Gui / Game.Kit / Game.Foundation / Game.Tactics …）住在 zan-lang
# 仓库的 packages/ 下，编译要带 --package-project 指向包根：仓库内 = 仓库根；
# 项目搬到仓库外后 = zan-lang 仓库，由 $ZAN_HOME 或 -PackageProject 指定。
# assets/ 由 zanc 自动内嵌进 exe（入口源文件带目录前缀时才会定位到），
# 这里再在 exe 旁留一份磁盘副本——运行时磁盘优先，换图即生效。
param(
    [string]$Compiler = $env:ZANC,
    [string]$Stdlib = $env:ZAN_STDLIB,
    [string]$Output = '',
    [string]$PackageProject = '',
    # 透传给 zanc 的额外参数（如 --publish --target android-arm64 ...）
    [string[]]$ZancArgs = @()
)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$repo = Split-Path -Parent $project
if (-not $Compiler) {
    $local = if ($env:ZAN_HOME) { Join-Path $env:ZAN_HOME 'build/zanc.exe' } else { '' }
    if ($local -and (Test-Path $local)) { $Compiler = $local } else { $Compiler = (Get-Command zanc -ErrorAction Stop).Source }
}
if (-not $Stdlib -and $env:ZAN_HOME) { $Stdlib = Join-Path $env:ZAN_HOME 'stdlib' }
if (-not $PackageProject) { if ($env:ZAN_HOME) { $PackageProject = $env:ZAN_HOME } else { throw '需要 $env:ZAN_HOME 指向 zan-lang 仓库（公共包在它的 packages/ 下）' } }
if (-not $Output) { $Output = Join-Path $repo 'build/voxel' }
$Output = [IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Force -Path $Output | Out-Null
# 入口 main.zan 必须排第一：zanc 只把 Main() 给第一个编译输入
# （genrun.c 的 emitMain=paths[0]）。其余 .zan 递归枚举——zanc 不会自动
# 带上同目录的其它文件，少传一个就是 "undefined type"。
$entry = Join-Path $project 'src/main.zan'
$sources = @()
if (Test-Path $entry) { $sources += $entry }
$sources += @(Get-ChildItem (Join-Path $project 'src') -Recurse -File -Filter *.zan |
    Where-Object { $_.FullName -ne $entry } | Sort-Object FullName | ForEach-Object { $_.FullName })
$zargs = @($sources) + @('--auto-stdlib', '--package-project', $PackageProject)
if ($Stdlib) { $zargs += @('--stdlib-path', $Stdlib) }
if ($ZancArgs) { $zargs += $ZancArgs }
$exe = Join-Path $Output 'Voxel.exe'
$zargs += @('-o', $exe)
& $Compiler @zargs
if ($LASTEXITCODE -ne 0) { throw "zanc failed ($LASTEXITCODE)" }
$assets = Join-Path $project 'assets'
# 先清掉上一版残留（素材改过名时，老文件留着只会误导），再整份拷过去。
$outAssets = Join-Path $Output 'assets'
if (Test-Path $outAssets) { Remove-Item $outAssets -Recurse -Force }
if (Test-Path $assets) { Copy-Item $assets $Output -Recurse -Force }
# 皮肤包必须与 exe 同级：build/voxel/skins/voxel/skin.css
# （Gui.Styling.Skin.Roots 查的是 exe 同级 skins/ 与 assets/skins/）。
$skinSrc = Join-Path $assets 'skins/voxel'
if (Test-Path $skinSrc) {
    $skinDst = Join-Path $Output 'skins/voxel'
    New-Item -ItemType Directory -Force -Path $skinDst | Out-Null
    Copy-Item (Join-Path $skinSrc '*') $skinDst -Recurse -Force
}
# 控件基线 base.css 跟皮肤包放在一起：Gui 只在磁盘上找它（没有内嵌
# 兜底），缺了它整层组件基线就没了，控件会退回硬编码的系统外观。
$baseCss = Join-Path $PackageProject 'packages/Zan.Gui/src/Gui/skins/base.css'
if (Test-Path $baseCss) {
    $skinsDir = Join-Path $Output 'skins'
    New-Item -ItemType Directory -Force -Path $skinsDir | Out-Null
    Copy-Item $baseCss (Join-Path $skinsDir 'base.css') -Force
}
Write-Host "Built $exe"