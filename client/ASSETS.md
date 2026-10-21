# voxel · 立方世界 · 素材清单

本清单描述**已经入库**的素材（`client/assets/`），不是计划。
总量：**位图 8 张 + 音效 7 个 = 614 KB**（口径 0.3~1.5 MB）。

全部素材为本项目自制：AI 生成后经 `client/tools/make_assets.py` 抠底/裁边/缩放
入库，或由该脚本程序化合成。**不含任何第三方素材**（早期版本提到过的
MineClone2 / VoxeLibre 只作玩法参考，仓库里没有它的任何文件，也没有 `LEGAL.md`
待核对的复制链——本次交付不使用它）。

---

## 一、位图（8 张）

| 文件 | 像素尺寸 | 显示尺寸 | 用途 | 来源 |
|---|---|---|---|---|
| `bg_sky.png` | 1024×640（P，160 色量化） | 拉伸铺满 1280×800 舞台 | 场景与菜单的远景天空（像素风体素山景） | AI 生成（gpt-image-2.5）→ 裁 16:10 → LANCZOS 缩放 → 调色板量化 |
| `title.png` | 960×240（RGBA，透明底） | 480×120 | 菜单标题牌匾 | AI 生成 → 洪泛抠黑底 → 裁边 → 放大 2 倍 → 降色深（posterize）压体积 |
| `blueprint.png` | 520×360（RGBA，透明底） | 236×168 | 左侧图纸卡（羊皮纸 + 网格） | 同上 |
| `player.png` | 96×128（RGBA，透明底） | 48×64 | 玩家角色立绘（体素矿工） | 同上 |
| `block_grass.png` | 128×128（RGBA） | 48×48 | 草方块：顶面草皮 + 侧面泥土带草沿 | **程序化**（PIL 像素画等距立方体） |
| `block_stone.png` | 128×128（RGBA） | 48×48 | 石方块：灰岩 + 裂纹斑点 | 程序化 |
| `block_wood.png` | 128×128（RGBA） | 48×48 | 木方块：顶面年轮 + 侧面竖向树皮 | 程序化 |
| `block_ore.png` | 128×128（RGBA） | 48×48 | 矿灯：暗岩底 + 发光晶簇 | 程序化 |

### 方块贴图的几何口径

等距 2:1。顶面菱形宽 48 / 高 24，一层立方体垂直边长 24。贴图在 64×64
的显示分辨率上作画，再 **NEAREST 放大 2 倍**入库（128×128）；运行时缩回
48×48，箱式滤波正好还原原始像素，边缘不糊。

三个面的亮度不同才有体积感：顶面 100%、左面 76%、右面 55%。

### 渲染路径（位图真的被画出来，不是摆设）

- 方块：`VoxelView.DrawBlock` → `CDraw.BlitImage(c, path, left, topY, 48, 48)`
- 角色：`VoxelView.DrawPlayer` → `CDraw.BlitImage(c, playerPath, left, topY, 48, 64)`
- 背景：`VoxelView.DrawScene` → `CDraw.BlitImage(c, bgPath, 0, 0, w, h)`
- 牌匾 / 图纸卡：`VoxelView.DrawMenu` / `DrawPlanCard` → `CDraw.BlitImage`

贴图找不到时（`Assets.Find` 落空）退回纯色几何绘制，**不崩**。

---

## 二、音效（7 个）

全部 `client/assets/sfx/*.wav`，格式 **22050 Hz / 16 bit / 单声道**，
由 `make_assets.py` 用 Python 合成（不经图像 API）。

| 文件 | 时长 | 触发时机 | 合成手法 |
|---|---|---|---|
| `step.wav` | 0.09 s | 玩家走了一格 | 噪声 × 指数衰减（软脚步） |
| `place.wav` | 0.16 s | 放置方块成功 | 150 Hz 正弦 + 极短噪声咔哒 |
| `break.wav` | 0.26 s | 破坏方块成功 | 低通噪声（砂砾）+ 90 Hz 低音 |
| `error.wav` | 0.22 s | 放置/破坏被拒（没材料、格子被占、越界） | 方波交替（150/104 Hz）蜂鸣 |
| `complete.wav` | 0.50 s | 一张图纸建成、解锁下一张 | C-E-G-C 琶音 |
| `win.wav` | 0.80 s | 三张图纸全部建成（通关） | 六音上行 + 下行收尾 |
| `fail.wav` | 0.70 s | 材料耗尽或超时（失败结算） | 四音下行 |

播放走公共包 `Game.Foundation.SfxBank`（磁盘优先 + 内嵌兜底 + 限频 +
无音频设备时静默降级），项目侧只声明名字与事件
（`client/src/VoxelSfx.zan`）。**没有声卡时静默失效，不崩不卡。**

---

## 三、怎么重新生成

```powershell
# 1) 生成 4 张 AI 原图（原始图落在 build/raw/，不入库）
pwsh -File client\tools\gen_images.ps1      # 需要 OPENAI_API_KEY
#    单张生成：
#    & "$HOME\.codex\skills\local-image2\scripts\image2.ps1" generate `
#        --model gpt-image-2.5 --prompt "<英文提示词>" --size 1024x1024 `
#        --quality high --output-format png --out "<绝对路径>.png" --force

# 2) 抠底 / 裁边 / 缩放 / 程序化贴图 / 合成 WAV → 入库
python client\tools\make_assets.py

# 3) 重新编译并跑测试
pwsh -File client\tools\build.ps1 -PackageProject D:\project\zan-head
pwsh -File client\tools\test.ps1  -PackageProject D:\project\zan-head
```

`make_assets.py` 的处理链：

- **AI 原图**：RGBA 化 → 从四边洪泛抠掉纯黑底（阈值 26）→ 裁到内容边界 →
  等比塞进「显示尺寸 × 2」的画布 → 降色深（posterize，步长 8）压体积。
  `bg_sky.png` 是满幅远景，不抠底，改用调色板量化（160 色）。
- **方块贴图**：直接在 64×64 显示分辨率上程序化绘制等距立方体（顶面菱形 +
  左面 + 右面，三面亮度 100%/76%/55%），再 NEAREST 放大 2 倍。
- **音效**：`wave` 模块写 22050 Hz / 16 bit / 单声道 WAV。

> **原始生成图不入库**：`build/` 已被 `.gitignore` 忽略，`build/raw/` 下的
> 1024² 原图与脚本只作本地缓存，不进版本库；体检脚本也只统计入库资产。
