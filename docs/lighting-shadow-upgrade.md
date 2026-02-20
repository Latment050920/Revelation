# Lighting & Shadow Upgrade (Minecraft 1.21.11 / Iris + Sodium)

## 1) 当前 shader 架构探测报告

### 生态识别
- 本包是 **Iris Shader Pack**（README 明确标注 Iris 1.7+，并声明 OptiFine Incompatible）。
- 结论：本次改造遵循 Iris/ShaderLabPBR 路径，不引入 OptiFine 专属特性。

### 主渲染管线（world0）
- GBuffer 阶段：`gbuffers_*`（terrain/entities/water/hand/sky/weather 等）。
- 阴影阶段：`shadow.vsh` + `shadow.fsh`（调用 `program/shadow/Shadow.vert|frag`）。
- 延迟与合成阶段：`deferred*`, `composite*`, `prepare*`, `setup*`。
- 后处理：Bloom、曝光、色调映射、TAA、CAS、运动模糊等在 `program/post/*`。

### Shadow / AO / Volumetric / Post 现状
- 阴影：已有 PCSS + screen-space contact shadow。
- AO：支持 SSAO / GTAO（AO_ENABLED 切换）。
- 体积：已有 volumetric fog + cloud shadows。
- 后处理：Auto Exposure + AgX/ACES/GT tone mapping + Bloom。

### GBuffer/Color buffer 布局（来自 `config.glsl`）
- `colortex0`: scene HDR
- `colortex1`: history/scene
- `colortex3`: indirect/motion
- `colortex4`: reproject/bloom tiles
- `colortex6`: albedo/rain alpha
- `colortex7`: material pack
- `colortex8`: normal/LDR
- `colortex11`: volumetric+depth（half res）
- `colortex12`: water/bloomy fog mask
- `colortex14`: variance history

### 关键宏与 uniform
- 阴影：`shadowMapResolution`, `shadowDistance`, `PCSS_*`, `SCREEN_SPACE_SHADOWS_*`
- AO：`AO_ENABLED`, `SSAO_*`, `GTAO_*`
- 后处理：`TONE_MAPPER`, `EXPOSURE_MODE`, `AUTO_EV_*`, `BLOOM_*`
- uniform：`worldSunVector`, `shadowProjection`, `shadowModelView`, `frameCounter`, `frameTime` 等。

---

## 2) 本次改造内容

### 阴影系统
- 新增阴影参数：
  - `SHADOW_FILTER_SCALE`
  - `SHADOW_SOFTNESS`
  - `SHADOW_BIAS_PRESET`（保守/均衡/激进）
  - `SHADOW_TEMPORAL_STABILITY`
- 强化 PCSS：
  - 过滤半径支持全局缩放；软阴影强度可调。
  - 采样旋转改为“稳定噪声 + dither 混合”，降低 shimmering。
- 偏移改造：
  - 引入 `CalculateShadowBias()`，按 `NdotL`（slope）+ 太阳高度自适应，减少 acne 与 Peter-panning。

### AO 系统
- 新增 `AO_TEMPORAL_STABILITY`，用于 AO 结果稳态混合，减少闪烁与“黑糊”感。
- AO 样本参数与档位联动（LITE/BALANCED/ULTRA）。

### 光照与后处理
- Bloom 新增保护参数：
  - `BLOOM_THRESHOLD`
  - `BLOOM_CLAMP`
- Tone mapping 新增：
  - `TONEMAP_CONTRAST`
- 自动曝光稳定化：
  - 新增 `EXPOSURE_STABILITY`
  - 在 `AutoExposure.comp` 中限制单帧曝光跃迁并平滑响应，降低进洞/出洞突变。

### 参数化与三档预设
- 新增 `QUALITY_PRESET`：`LITE / BALANCED / ULTRA`
- 同步提供 profile：`profile.LITE`, `profile.BALANCED`, `profile.ULTRA`
- 档位影响：
  - **LITE**：PCSS、SSS contact、AO、体积步数下降，显著节省 GPU 时间。
  - **BALANCED**：默认质量，保留软阴影与稳定 AO。
  - **ULTRA**：提升 PCSS 与 AO 采样、体积步数，阴影边缘和远景体积更平滑（开销最高）。

性能主要消耗点：
1. PCSS 搜索/滤波样本数。
2. AO 样本（特别 GTAO direction × slices）。
3. Volumetric fog 步进数。
4. Bloom 合成与后处理链长度。

---

## 3) 固定场景对比复现指南（手动截图）

> 为保证可复现，建议关闭动态天气变化（或用命令锁定），并固定 FOV、分辨率、渲染距离。

通用设置：
1. 关闭随机种子变化因素：固定世界、固定坐标。
2. 固定相机：`F3` 记录 XYZ + Yaw/Pitch。
3. 每组测试切换同一 `QUALITY_PRESET` 与同一视角截图“改造前/后”。

### 场景 A：正午室外
- 时间：`/time set noon`
- 地点：平原，含树木+建筑边缘
- 看点：阴影边缘锯齿、接触阴影、远处稳定性

### 场景 B：黄昏逆光
- 时间：`/time set sunset`
- 地点：低矮山丘
- 看点：软阴影过渡、太阳色温与地平线过渡

### 场景 C：洞穴火把
- 时间：任意
- 地点：中等深度洞穴
- 看点：自动曝光稳定性、暗部细节、AO 是否发黑

### 场景 D：室内窗边
- 时间：`/time set noon`
- 地点：室内单侧窗户
- 看点：窗边高亮不过曝、阴影细腻度

### 场景 E：雨天/雾天
- 天气：`/weather rain`
- 看点：volumetric + bloom 不发白，层次保留

---

## 4) 兼容性与许可
- 兼容目标：Minecraft Java 1.21.11 + Iris + Sodium（优先）。
- 未引入第三方受限代码/资源；仅在原仓库 shader 代码内改造。
