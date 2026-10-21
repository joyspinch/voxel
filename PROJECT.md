# 立方世界 · VOXEL —— 等距体素建造

> 一个"按图纸把方块垒起来"的等距（2.5D）体素建造游戏。
> 玩法闭环：**按图纸逐格放置 → 每格类型与位置都对 → 图纸建成、解锁下一张 →
> 全部建成结算；材料耗尽或超时则失败结算。**
> 素材清单见 [`client/ASSETS.md`](client/ASSETS.md)，交付标准见
> `D:\project\zan-lang\docs\REAL_GAME_STANDARD.md`。

---

## 一、玩法

### 世界

- 三维体素网格 **32 × 8 × 32**（x 向右、y 向上、z 向里）。
- 方块类型：**草 / 石 / 木 / 矿灯**四种（+ 空气）。
- 地形是起伏的草皮台地（正弦叠加生成），零星石头与矿灯，稀树（木干 + 草冠）。
  **工地（12..20 见方）与出生平台是推平的**，图纸才能从零建起。
- 渲染是等距 2:1：顶面菱形 48×24，一层立方体垂直边长 24；按 `x+z` 升序
  （同深度再按 `y` 升序）画家算法画方块，前后遮挡正确。

### 目标：三张图纸，逐张解锁

| # | 名称 | 要求 | 限时（标准难度） |
|---|---|---|---|
| 1 | 石台 | 3×3 石台铺地基（9 石） | 100 s |
| 2 | 灯柱 | 台心立木柱，柱顶挂矿灯（2 木 + 1 矿） | 100 s |
| 3 | 瞭望塔 | 四角木柱挑矿灯，顶上盖草棚（8 木 + 4 矿 + 4 草） | 220 s |

判定口径：**每格都要类型与位置都对**才算建成——只看数量不算，只看位置不算。

### 资源与失败

- 背包初始：**草 6 / 石 11 / 木 12 / 矿灯 7**（需求是 石 9 / 木 10 / 矿 5 / 草 4，
  留一点容错）。
- 破坏方块**回收少量资源**：草 / 石 / 木各回 1 个；**矿灯拆了不回收**——
  矿灯是整局最稀缺的材料，放错就白放。
- **失败条件**：① 背包材料不够把当前图纸建完（缺口 > 库存）；② 当前图纸超时。
  两种都进结算面板，写清失败原因。
- **成长**：累计建成图纸数、累计放置方块数、最快通关用时、出场次数都进存档，
  菜单与结算面板都显示。

---

## 二、怎么玩

| 操作 | 按键 |
|---|---|
| 移动 | `W A S D` / 方向键（一格 170 ms，可以上一级台阶、往下跳，两格以上的高墙挡住） |
| 选材料 | `1` 草 / `2` 石 / `3` 木 / `4` 矿灯，或直接点底部背包条 |
| 升降建造高度 | `Q` 降 / `E` 升（相对角色所处层，−3 ~ +5） |
| 放置 | **鼠标左键**——放在**面朝方向的相邻格**、当前建造高度那一层 |
| 破坏 | **鼠标右键**——同一格 |
| 设置 | `Esc`（建造时限宽松/标准/紧张、图纸提示开关） |

**光标**：角色脚下一圈高亮菱形 = 目标格（可放亮黄、不可放亮红），
下面那根竖线连到地面，标示当前建造高度。
左侧羊皮纸图纸卡显示图纸名、进度条与材料清单；场景里未满足的格子画黄框提示。

**提示**：图纸二建在图纸一的石台上，所以要先把石台垒起来、踩上去，
再用 `E` 把建造高度抬到 2~4 层往上砌。

---

## 三、怎么跑

```powershell
$env:ZAN_HOME = 'D:\project\zan-lang'          # 编译器与 stdlib 同源
pwsh -File client\tools\build.ps1 -PackageProject D:\project\zan-head
# 产出 build/voxel/Voxel.exe（assets/ 会一并复制到 exe 旁，运行时磁盘优先）
```

- 编译用 `D:\project\zan-lang\build\zanc.exe`；`-PackageProject` 指向
  公共包所在的 zan-lang 仓库（仓库内 = 仓库根，仓库外 = zan-lang 仓库）。
- 想连包一起发单文件：`pwsh -File client\tools\build.ps1 -ZancArgs '--publish'`。

### 环境变量（调试用）

| 变量 | 作用 |
|---|---|
| `VOXEL_SMOKE=1` | 无头冒烟：直接进工地并自动建造，跑满 `VOXEL_FRAMES` 帧后自行退出 |
| `VOXEL_FRAMES=<n>` | 冒烟帧数（默认 90） |
| `VOXEL_AUTOSTART=1` | 跳过菜单直接进工地（截图/演示用） |
| `VOXEL_AUTOBUILD=1` | 自动按图纸建造（配合上面的两个） |
| `VOXEL_CAPTURE=<path.zpx>` | 第 60 帧写画布像素（**调试用**；验收截图请抓窗口像素） |
| `VOXEL_SAVE=<dir>` | 存档目录（默认 `%LOCALAPPDATA%/Voxel`） |

---

## 四、怎么测

```powershell
pwsh -File client\tools\test.ps1 -PackageProject D:\project\zan-head
```

三段全绿才算过：

| 段 | 判据 |
|---|---|
| `voxel_test_OK` | 玩法断言 269 条：三维存取一致性、越界拒绝放置、放置后格子类型改变、资源减少、破坏回收资源（矿灯不回收）、图纸判定要求类型与位置都对、图纸逐张解锁、等距投影随 x 单调右移、玩家被方块阻挡、三种子跑完整局且蓝图进度自洽 |
| `voxel_SAVE_OK runs=1 -> runs=2` | 存档写两遍读得到（第二遍是新进程，必须读回第一遍写的档） |
| `voxel_SMOKE_OK` | 无头冒烟跑满帧自行退出（帧计数放在 `Update()`，窗口不可见时宿主跳过渲染） |

截图验收（抓**窗口像素**，不是画布）：

```powershell
python D:\project\zan-lang\scripts\shot_window.py `
    build\voxel\Voxel.exe build\voxel\shot.png 2.0 build\voxel
```

---

## 五、目录

```
voxel/
  client/
    src/           玩法与渲染代码（10 个 .zan，分模块）
      main.zan         GuiHost 入口
      VoxelGame.zan    状态机：菜单 / 建造 / 结算 + 输入 + 存档结算
      VoxelWorld.zan   三维网格存取 + 地形生成
      VoxelIso.zan     等距投影与遮挡排序
      VoxelBuild.zan   放置 / 破坏 / 背包资源
      VoxelBlueprint.zan 图纸定义与判定
      VoxelView.zan    渲染 + 贴图加载 + HUD + 菜单 + 结算
      VoxelPaint.zan   逻辑坐标画布原语
      VoxelSfx.zan     音效事件
      GameShell.zan    存档 + 设置 + 设置浮层
    assets/        8 张位图 + assets/sfx/ 7 个 WAV
    tests/         voxel_test.zan（玩法断言）
    tools/         build.ps1 / test.ps1 / make_assets.py / gen_images.ps1
    ASSETS.md      素材清单
  build/           编译产物与本地原图缓存（.gitignore 忽略，不入库）
  PROJECT.md
```

## 六、实现要点（踩过的坑）

- **Zan 保留字**：`base` / `out` / `where` 是关键字，标识符不能以它们开头
  （地形生成里原本写的 `base` 被编译期拦下，改成 `trunk`）。
- **`CDraw.BlitImageSrc` 在公共包里还不存在**（干净 worktree 的
  `Game.Kit.CDraw` 只有 `BlitImage` / `BlitSource`）。要裁源矩形就自己算：
  `CDraw.BlitSource(c, path)` 拿 key，再配 `CDraw.MapX/MapY/MapW` 调底层
  `Canvas.BlitImage(key, dx, dy, dw, dh, sx, sy, sw, sh)`。本项目用不到裁剪，
  直接 `CDraw.BlitImage` 整幅缩放。
- **角色必须压在场景上层**：地形有高差，深度正确的画家算法会把人整个埋进
  崖壁后面，玩家看不见自己就没法玩。所以方块按深度画完，角色最后画。
- **建造高度与相邻格是两件事**：目标格 = 面朝方向的相邻格 + 当前建造高度。
  高度是**相对角色所处层**的偏移（`cursorOffset`，−3 ~ +5），与角色站在哪
  一层无关——所以角色站在地面上（身体占 y=1）也能把光标抬到 y=2、y=3 往上盖。
  目标格永远是**相邻格**，不会落在角色自己脚下那一格。
- **世界绘制不要额外的排序结构**：`(x+z)` 升序 + 同深度 `y` 升序的嵌套循环
  就能出正确的前后关系。
