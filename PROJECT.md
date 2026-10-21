# 立方世界 —— 3D 方块沙盒（真 3D）

> 本文件是 voxel 项目的落地说明。**素材清单见 `client/ASSETS.md`**，全局规格见工作区根的 `ASSET-PIPELINE.md`。

## 参考源与授权边界

- **参考**：MineClone2 / VoxeLibre（素材以 CC BY-SA 3.0 为主，逐文件见 `LEGAL.md`）
- **抄什么**：抄方块世界生成、挖掘/放置、物品栏、合成、生物群系。贴图与图标自研。

**红线与差异**：

- MineClone2 素材含 Minecraft 1.11 的 Pixel Perfection 复制链，**该包不取用**。
- CC BY-SA 传染，衍生作品须同协议 + 署名；闭源商业化前须逐件核对 `LEGAL.md`。
- Zan 无 glTF/FBX 加载器，方块网格顶点需手写常量（`AddCube` 顶点为 -1..1，缩放取半边长）。

## 渲染路线

**真 3D（GPU）**：`Mesh3D.AddCube` + `Mat4.Perspective/LookAt` + `MeshBatch` 实例化。已实测 `Canvas.SetBackend(1)` → `Backend()=="gl"`，网格批量落像素。

> **⚠ 3D Y 轴必须手动修正**：GPU 3D 管线的顶点着色器对 `clip.y` 取负（`zan-lang/src/runtime/zan_game.c` 的 `ZAN_GAME_3D_VS_*`），而 2D 画布是 y 向下，两者方向相反。直接用 `Mat4.Perspective` + `Mat4.LookAt` 画出来的 3D 内容相对 2D 层**上下颠倒**（地平线在上、天空在下）。修法是建投影后把 `p.m[5]` 取负，两次翻转抵消：
> ```zan
> Mat4 p = Mat4.Perspective(1.0472f, (float)cw / (float)ch, 0.1f, 200.0f);
> p.m[5] = -p.m[5];   // 与 GPU 着色器的 -clip.y 抵消
> ```
> `voxel` 与 `racekart` 已按此修正；**新增真 3D 项目必须照做**。

## 目录

    voxel/
      client/       src/ 源码、assets/ 素材、data/ 数据、skins/ 皮肤、tools/ 脚本、tests/ 用例
      build/        编译产物（不入库）

所有命令都在**项目根**下执行（路径相对项目根）。

## 编译

```powershell
$env:ZAN_HOME = 'D:/project/zan-lang'   # 编译器与 stdlib 同源；公共包在它的 packages/ 下
pwsh -File client/tools/build.ps1
```

ZAN_HOME 指向 zan-lang 仓库时用它的 `build/zanc.exe` 与 `stdlib/`；不设则用 PATH 上的 `zanc`。
编译时加 `--package-project $env:ZAN_HOME` 可直接吃仓库里的 `packages/`。

## 测试

```powershell
pwsh -File client/tools/test.ps1     # 无头冒烟：跑满 90 帧后自行退出
```

工作区批量冒烟：`pwsh -File tools/smoke-all.ps1`（一次跑完 10 个新项目）。

## 当前状态

骨架可编译可运行，真 3D 渲染已出实证截图（`build/voxel/voxel_fix.png`，1920×1200，GPU mesh batch 渲染 524 个体素柱）。
另：首次实拍发现 3D 相对 2D 层上下颠倒，已定位到 GPU 着色器的 `-clip.y` 并用 `p.m[5] = -p.m[5]` 修正（见上）。

## 后续（按优先级）

1. 接入真实位图 sprite 与音效（素材见 `client/ASSETS.md`）。
2. 补玩法深度：参照源的关卡/数值/AI 三个维度逐项对齐。
3. 需要时再评估联网（`legend` 有服务端可参考）。