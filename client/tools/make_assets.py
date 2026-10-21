#!/usr/bin/env python3
"""make_assets.py —— 立方世界 · VOXEL 的素材流水线。

三段：
  1. **AI 原图后处理**（build/raw/*.png）：抠黑底（洪泛）→ 裁边 → 缩放到
     显示尺寸 2 倍 → 存入 client/assets/。原图不留在项目里。
  2. **程序化等距方块贴图**：像素画风格的等距立方体（顶面 + 左右侧面，
     三面亮度不同才有体积感），画在 64×64 显示分辨率上，NEAREST 放大 2 倍
     入库（运行时缩回 64×64 正好还原原始像素，边缘不糊）。
  3. **音效合成**：Python 直接写 WAV（22050Hz / 16bit / 单声道）。

用法：python client/tools/make_assets.py [--raw build/raw]
"""

import argparse
import math
import os
import struct
import sys
import wave
from collections import deque

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS = os.path.join(ROOT, "client", "assets")
SFX = os.path.join(ASSETS, "sfx")

TILE = 64          # 显示分辨率：等距方块贴图 64×64
BLOCK_W = 64       # 显示尺寸：等距方块 64 宽 × 64 高
PLAYER_W = 48      # 玩家立绘显示尺寸 48×64
PLAYER_H = 64


# --------------------------------------------------------------------------
# 1. AI 原图后处理
# --------------------------------------------------------------------------

def flood_remove_black(img, threshold=26):
    """从四边洪泛抠掉纯黑底，返回带 alpha 的 RGBA。"""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    seen = bytearray(w * h)
    q = deque()
    for x in range(w):
        q.append((x, 0))
        q.append((x, h - 1))
    for y in range(h):
        q.append((0, y))
        q.append((w - 1, y))
    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= w or y >= h:
            continue
        idx = y * w + x
        if seen[idx]:
            continue
        r, g, b, a = px[x, y]
        if r >= threshold or g >= threshold or b >= threshold:
            continue
        seen[idx] = 1
        px[x, y] = (r, g, b, 0)
        q.append((x + 1, y))
        q.append((x - 1, y))
        q.append((x, y + 1))
        q.append((x, y - 1))
    return img


def trim(img):
    bbox = img.getbbox()
    if bbox is None:
        return img
    return img.crop(bbox)


def fit_into(img, tw, th):
    """等比缩放塞进 tw×th 的画布（居中，透明底）。"""
    canvas = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    ratio = min(tw / img.width, th / img.height)
    nw = max(1, int(round(img.width * ratio)))
    nh = max(1, int(round(img.height * ratio)))
    small = img.resize((nw, nh), Image.LANCZOS)
    canvas.paste(small, ((tw - nw) // 2, (th - nh) // 2), small)
    return canvas


def save_rgba(img, dst):
    """带 alpha 的图：保留 RGBA（量化会破坏透明边缘的平滑度）。"""
    img.save(dst, optimize=True)
    print("asset", os.path.basename(dst), img.size)


def posterize_rgba(img, step=8):
    """把颜色量化到 step 的整数倍：平坦化后 PNG 压得动，视觉几乎无损。"""
    w, h = img.size
    px = img.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            px[x, y] = (r // step * step, g // step * step, b // step * step, a)
    return img


def save_opaque(img, dst, colors=192):
    """不透明的大图走调色板量化：渐变天空 PNG 从 1MB 压到 ~120KB。"""
    img = img.convert("RGB")
    q = img.quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.FLOYDSTEINBERG)
    q.save(dst, optimize=True)
    print("asset", os.path.basename(dst), q.size)


def process_ai(src, dst, disp_w, disp_h, trim_bg=True):
    """抠底 → 裁边 → 放大 2 倍 → 入库（角色走透明通道）。"""
    if not os.path.exists(src):
        print("MISSING", src)
        return False
    img = Image.open(src).convert("RGBA")
    if trim_bg:
        img = flood_remove_black(img)
        img = trim(img)
    out = fit_into(img, disp_w * 2, disp_h * 2)
    save_rgba(out, dst)
    return True


def process_plate(src, dst, disp_w, disp_h):
    """面板类素材：抠掉纯黑底留透明通道；再降色深（posterize）压体积。"""
    if not os.path.exists(src):
        print("MISSING", src)
        return False
    img = Image.open(src).convert("RGBA")
    img = flood_remove_black(img)
    img = trim(img)
    out = fit_into(img, disp_w * 2, disp_h * 2)
    out = posterize_rgba(out)
    save_rgba(out, dst)
    return True


def process_background(src, dst, w, h):
    """背景图是满幅的，不抠底：裁成目标比例再缩放。"""
    if not os.path.exists(src):
        print("MISSING", src)
        return False
    img = Image.open(src).convert("RGB")
    target = w / h
    cur = img.width / img.height
    if cur > target:
        nw = int(img.height * target)
        img = img.crop(((img.width - nw) // 2, 0, (img.width + nw) // 2, img.height))
    else:
        nh = int(img.width / target)
        img = img.crop((0, (img.height - nh) // 2, img.width, (img.height + nh) // 2))
    img = img.resize((w, h), Image.LANCZOS)
    save_opaque(img, dst, colors=160)
    return True


# --------------------------------------------------------------------------
# 2. 程序化等距方块贴图
# --------------------------------------------------------------------------

def _hash(x, y, seed):
    n = (x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)
    n = (n ^ (n >> 13)) & 0xFFFFFFFF
    n = (n * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def _clamp_rgb(r, g, b):
    return (max(0, min(255, int(r))), max(0, min(255, int(g))), max(0, min(255, int(b))))


def _shade(rgb, k):
    return _clamp_rgb(rgb[0] * k, rgb[1] * k, rgb[2] * k)


def tex_grass_top(u, v, seed):
    n = _hash(u, v, seed)
    base = (88, 158, 60)
    if n > 0.90:
        return _clamp_rgb(base[0] + 34, base[1] + 40, base[2] + 18)
    if n < 0.12:
        return _clamp_rgb(base[0] - 26, base[1] - 34, base[2] - 14)
    return _shade(base, 0.92 + n * 0.16)


def tex_grass_side(u, v, seed):
    """侧面：顶部一条草沿，下面是泥土。"""
    dirt = (128, 92, 56)
    if v < 5:
        return tex_grass_top(u, v + 40, seed)
    n = _hash(u, v, seed + 7)
    if n > 0.93:
        return _clamp_rgb(dirt[0] - 34, dirt[1] - 26, dirt[2] - 18)
    if n < 0.10:
        return _clamp_rgb(dirt[0] + 26, dirt[1] + 20, dirt[2] + 14)
    return _shade(dirt, 0.9 + n * 0.2)


def tex_stone(u, v, seed):
    base = (126, 128, 134)
    n = _hash(u, v, seed)
    m = _hash(u // 4, v // 4, seed + 3)
    if m > 0.88:
        return _clamp_rgb(base[0] - 34, base[1] - 34, base[2] - 28)
    if n > 0.94:
        return _clamp_rgb(base[0] + 30, base[1] + 30, base[2] + 26)
    return _shade(base, 0.88 + n * 0.22)


def tex_wood_top(u, v, seed):
    """顶面：年轮（同心方环）。"""
    cx = u - 31.5
    cy = v - 31.5
    d = math.sqrt(cx * cx + cy * cy)
    ring = int(d // 3.0) % 2
    light = (166, 120, 68)
    dark = (122, 84, 46)
    col = light if ring == 0 else dark
    n = _hash(u, v, seed)
    return _shade(col, 0.9 + n * 0.2)


def tex_wood_side(u, v, seed):
    """侧面：竖直树皮条纹。"""
    bark = (104, 72, 42)
    stripe = _hash(u, 0, seed)
    if stripe > 0.80:
        return _shade(bark, 0.68)
    if stripe < 0.18:
        return _shade(bark, 1.22)
    n = _hash(u, v, seed)
    return _shade(bark, 0.9 + n * 0.2)


def tex_ore(u, v, seed):
    """矿灯：暗岩底 + 发光晶簇。"""
    base = (74, 76, 84)
    n = _hash(u, v, seed)
    if n > 0.90:
        return (86, 226, 255)
    if n > 0.84:
        return (44, 150, 186)
    if n > 0.80:
        return (250, 206, 84)
    return _shade(base, 0.86 + n * 0.28)


BLOCKS = [
    ("block_grass.png", tex_grass_top, tex_grass_side, 11),
    ("block_stone.png", tex_stone, tex_stone, 23),
    ("block_wood.png", tex_wood_top, tex_wood_side, 37),
    ("block_ore.png", tex_ore, tex_ore, 53),
]


def make_block(name, top_fn, side_fn, seed):
    """画 64×64 的等距立方体（顶面 + 左面 + 右面），再 NEAREST 放大 2 倍。"""
    w = h = TILE
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    cx = w / 2.0
    for x in range(w):
        # 顶面菱形：|x-cx|/32 + |y-16|/16 <= 1
        for y in range(0, 32):
            if abs(x - cx) / 32.0 + abs(y - 16) / 16.0 <= 1.0:
                px[x, y] = top_fn(x, y, seed) + (255,)
        # 左面：上沿 y=16+x/2，下沿 y=48+x/2
        ytop = 16 + x / 2.0
        ybot = 48 + x / 2.0
        for y in range(int(math.ceil(ytop)), int(math.floor(ybot)) + 1):
            if 0 <= y < h:
                col = side_fn(x, y - int(ytop), seed)
                px[x, y] = _shade(col, 0.76) + (255,)
        # 右面：上沿 y=48-x/2（以菱形右顶点收口），下沿 y=56-x/2 ... 见下
        ytop_r = 32 - (x - 32) / 2.0
        ybot_r = 64 - (x - 32) / 2.0
        for y in range(int(math.ceil(ytop_r)), int(math.floor(ybot_r)) + 1):
            if 0 <= y < h:
                col = side_fn(x - 32, y - int(ytop_r), seed)
                px[x, y] = _shade(col, 0.55) + (255,)
    big = img.resize((w * 2, h * 2), Image.NEAREST)
    out = os.path.join(ASSETS, name)
    big.save(out)
    print("asset", name, big.size)


# --------------------------------------------------------------------------
# 3. 音效合成
# --------------------------------------------------------------------------

RATE = 22050


def _write_wav(name, samples):
    os.makedirs(SFX, exist_ok=True)
    path = os.path.join(SFX, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = bytearray()
        for s in samples:
            v = int(max(-1.0, min(1.0, s)) * 32000)
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))
    print("sfx", name, len(samples) / RATE)


def _env(i, n, attack=0.01, release=0.6):
    t = i / RATE
    total = n / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    r = max(0.0, 1.0 - max(0.0, (t - total * (1.0 - release)) / (total * release))) if release > 0 else 1.0
    return a * r


def sfx_place():
    n = int(RATE * 0.16)
    out = []
    for i in range(n):
        t = i / RATE
        e = _env(i, n, 0.002, 0.85)
        tone = math.sin(2 * math.pi * 150 * t) * 0.6
        click = (_hash(i, 3, 5) - 0.5) * math.exp(-t * 90) * 0.7
        out.append((tone + click) * e * 0.75)
    return out


def sfx_break():
    n = int(RATE * 0.26)
    out = []
    prev = 0.0
    for i in range(n):
        t = i / RATE
        e = _env(i, n, 0.002, 0.9)
        noise = (_hash(i, 7, 11) - 0.5) * 2.0
        prev = prev * 0.55 + noise * 0.45     # 低通，砂砾感
        low = math.sin(2 * math.pi * 90 * t) * 0.35
        out.append((prev * 0.8 + low) * e * 0.7)
    return out


def sfx_step():
    n = int(RATE * 0.09)
    out = []
    for i in range(n):
        t = i / RATE
        e = math.exp(-t * 70)
        noise = (_hash(i, 11, 17) - 0.5) * 2.0
        out.append(noise * e * 0.35)
    return out


def sfx_error():
    n = int(RATE * 0.22)
    out = []
    for i in range(n):
        t = i / RATE
        e = _env(i, n, 0.004, 0.7)
        f = 150 if (int(t * 22) % 2 == 0) else 104
        out.append(math.sin(2 * math.pi * f * t) * e * 0.42)
    return out


def _arp(notes, dur, vol):
    n = int(RATE * dur)
    out = []
    seg = n // len(notes)
    for i in range(n):
        idx = min(len(notes) - 1, i // seg)
        t = (i - idx * seg) / RATE
        e = math.exp(-t * 5.0)
        f = notes[idx]
        s = math.sin(2 * math.pi * f * t) * 0.7
        s += math.sin(2 * math.pi * f * 2 * t) * 0.22
        out.append(s * e * vol)
    return out


def sfx_complete():
    return _arp([523.25, 659.25, 783.99, 1046.5], 0.5, 0.5)


def sfx_win():
    return _arp([523.25, 659.25, 783.99, 1046.5, 1318.5, 1046.5], 0.8, 0.55)


def sfx_fail():
    return _arp([392.0, 329.6, 261.6, 196.0], 0.7, 0.5)


# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default=os.path.join(ROOT, "build", "raw"))
    args = ap.parse_args()
    raw = args.raw

    os.makedirs(ASSETS, exist_ok=True)
    os.makedirs(SFX, exist_ok=True)

    # AI 原图 → 入库资产
    process_ai(os.path.join(raw, "player.png"),
               os.path.join(ASSETS, "player.png"), PLAYER_W, PLAYER_H)
    process_plate(os.path.join(raw, "title.png"),
                  os.path.join(ASSETS, "title.png"), 480, 120)
    process_plate(os.path.join(raw, "blueprint.png"),
                  os.path.join(ASSETS, "blueprint.png"), 260, 180)
    process_background(os.path.join(raw, "bg_sky.png"),
                       os.path.join(ASSETS, "bg_sky.png"), 1024, 640)

    # 程序化等距方块
    for name, top_fn, side_fn, seed in BLOCKS:
        make_block(name, top_fn, side_fn, seed)

    # 音效
    _write_wav("place", sfx_place())
    _write_wav("break", sfx_break())
    _write_wav("step", sfx_step())
    _write_wav("error", sfx_error())
    _write_wav("complete", sfx_complete())
    _write_wav("win", sfx_win())
    _write_wav("fail", sfx_fail())

    total = 0
    for dirpath, _, names in os.walk(ASSETS):
        for n in names:
            total += os.path.getsize(os.path.join(dirpath, n))
    print("assets total bytes:", total)
    return 0


if __name__ == "__main__":
    sys.exit(main())
