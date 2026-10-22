# 立方世界 构建：编译 client/src/ 下全部 .zan → 可执行文件。
#
# 公共包（Gui / Game.Kit / Game.Foundation / Game.Tactics …）住在 zan-lang
# 仓库的 packages/ 下，编译要带 --package-project 指向包根。
#
# 公共包**直接用主仓**（只读），不要建 git worktree 副本：副本停在旧 commit
# 上，公共包一改就不跟（已因此出过故障）。包根用 $ZAN_HOME 或 -PackageProject
# 指定。
#
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
if (-not $PackageProject) {
    # 公共包根 = 主仓 zan-lang（packages/ 在它下面）。$ZAN_HOME 优先。
    if ($env:ZAN_HOME) { $PackageProject = $env:ZAN_HOME }
    else { throw '需要 -PackageProject（或 $env:ZAN_HOME）指向 zan-lang 仓库——公共包在它的 packages/ 下' }
}
if (-not (Test-Path (Join-Path $PackageProject 'packages'))) {
    throw "公共包根下没有 packages/：$PackageProject"
}
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
# 清掉旧版遗留的磁盘 base.css（老构建拷过一份）：留着会盖住 exe 内嵌的
# 基线，让"内嵌兜底到底有没有生效"这件事永远测不出来。
$staleBase = Join-Path $Output 'skins/base.css'
if (Test-Path $staleBase) { Remove-Item $staleBase -Force }
# 控件基线 base.css **不在这里拷**：zanc 会自动内嵌 stdlib 的 Gui 皮肤基线
# （含 base.css 与 dark/light——见 src/compiler/main.c 的 skins 自动内嵌分支；
# embedres 的过滤器只作用于 depth-1 的皮肤包目录，base.css 是文件照内嵌）。
# 运行时 Gui 也是磁盘优先、内嵌兜底（Gui.Styling.Skin.BaseCss），所以 exe 旁
# 不必再放一份 base.css——省掉它还免了"磁盘旧基线盖住 exe 内嵌新基线"的漂移。
# 只有"整体替换基线"（自带完整 base.css 替身）才会让编译器跳过基线自动内嵌。
Write-Host "Built $exe"