# ARCHITECTURE_MAP.md — 7-world 架构对照表（按宪法归位）

> 目标：把仓库现有结构与《CONSTITUTION_7-world.md》逐条对齐，方便后续 DayX 扩展不跑偏。  
> 本表基于你当前仓库目录结构（摘录）：
>
> root
- main.tscn
- project.godot
- autoload/
- core/
  - camera/
  - layer/
  - time/
  - world/
- layers/
  - common/
  - shallow_sea/
  - deep_sea/
- ecology/
- entities/
- presentation/
- debug/
- player/


---

## 1) 全局数据流（你项目的“主干管线”）

1. **WorldRoot**（世界中枢）维护 `WorldState`（世界快照）、时间与当前层/列等浏览状态。  
2. **EcologyRules**（生态规则）只产出各层的 **Intent（建议值）**：`get_layer_intent(layer_index)` 或等价接口。  
3. **LayerBase**（层基类）每帧：`Intent -> Flatten -> InertiaField -> Applied`，写入 `LayerState.applied`。  
4. **Layer 子模块（Spawner / Visuals / Hazard / Vignette）**只读 `LayerState.applied` 执行：
   - 实体生成/回收（Spawner）
   - 视觉表现（Visuals / Vignette）
   - 危险/入侵等局部系统（Hazard）
5. **DebugOverlay / StateViewer**只读 `WorldState / LayerState / 模块快照` 展示。

---

## 2) 目录级“归位”与宪法条款映射

### 2.1 `core/`（核心机制层，最硬的底盘）
对应宪法：**1（状态/行为分离）/ 2（Intent→Applied）/ 5（层身份与顺序解耦）/ 7（参数可调）**

- `core/world/`
  - `world_root.gd`：**世界中枢写入者**（唯一允许统一更新 WorldState 的地方）
  - `world_state.gd`：世界快照（只存数据，不做逻辑）
  - `world_config.gd`：世界配置（层顺序、参数等，集中可调）
- `core/layer/`
  - `layer_base.gd`：Intent→Applied 的标准管线实现（惯性/限速/扁平化）
  - `layer_state.gd`：层快照（intent/applied/taus 等只读输出）
  - `inertia_field.gd`：惯性字段（按 key 管 tau/max_rate）
- `core/time/`
  - `world_clock.gd`：世界时间推进（tick/累积）
  - `world_time.gd`：时间数据/工具（若有）
- `core/camera/`
  - `camera_controller.gd`：相机控制/防抖（行为模块）
  - `world_camera.gd`：相机节点封装（表现与控制）

**违宪红线：**  
- 在 `world_state.gd / layer_state.gd` 内写规则分支（宪法 1 违宪）。  
- 在 `layer_base.gd` 里直接生成实体/改外部世界（宪法 3 违宪）。

---

### 2.2 `layers/`（层内容与层内黑盒模块）
对应宪法：**2（Intent→Applied）/ 3（黑盒模块）/ 7（参数可调）**

- `layers/common/`（可插拔子模块）
  - `layer_spawner.gd`：实体生成/回收（只读 applied）
  - `layer_visuals.gd`：层背景/色调/氛围表现（只读 applied）
  - `layer_warning_vignette.gd`：危险暗角/压迫感（只读 applied + enabled）
  - `layer_hazard.gd`：危险/入侵/污染等局部系统（只读 applied）
- `layers/shallow_sea/`
  - `shallow_sea_layer.gd`：浅海层（子类：提供 get_layer_intent + tau 分层）
  - `shallow_sea_config.gd`：浅海配置
  - `shallow_sea_layer.tscn`：浅海场景
- `layers/deep_sea/`
  - `deep_sea_layer.gd`：深海层（子类：提供 get_layer_intent + tau 分层）
  - `deep_sea_config.gd`：深海配置
  - `deep_sea_layer.tscn` & 临时 `.tmp`：场景文件（建议后续清理 tmp）

**违宪红线：**  
- 子模块跨层 `get_node` 访问别的层/世界结构（宪法 3 违宪）。  
- 子模块写回 intent / 修改其它模块内部状态（宪法 3.2 违宪）。

---

### 2.3 `ecology/`（生态系统：只产 Intent）
对应宪法：**2.1（Intent 是建议值）/ 3（黑盒）**

- `ecology_rules.gd`：按 layer_index 生成 Intent（只输出，不改世界）
- `ecology_layer_state.gd`：生态侧的层状态（如有）
- `prosperity.gd / diversity.gd`：子规则模块
- `invasion_controller.gd`：入侵风险/强度规则（仍应只产建议值，或产“生态态”供 rules 读取）

**违宪红线：**  
- 生态模块直接生成实体/改视觉/改相机（宪法 1/2 违宪）。

---

### 2.4 `entities/`（实体：最小行为 + 可视节点）
对应宪法：**3（黑盒）**

- `entities/base/entity_base.gd`：基础实体
- `entities/fish/fish.gd` + `fish.tscn`：鱼
- `entities/algae/algae.gd` + `algae.tscn`：水草

**约束建议：**  
- 实体尽量不要读世界结构；只做自身运动/动画/寿命等“局部逻辑”。

---

### 2.5 `presentation/`（世界级表现映射：从状态到画面风格）
对应宪法：**3（黑盒）/ 7（参数可解释）**

- `visual_mapper.gd`：状态→视觉映射（推荐只读 WorldState/LayerState）
- `atmosphere.gd`：氛围
- `rare_phenomena.gd`：稀有现象/事件表现（如果是“表现”，就别做规则）

---

### 2.6 `debug/`（只读观测）
对应宪法：**4（Debug 只观察）**

- `debug_overlay.gd`：HUD 显示 WorldState/Intent/Applied/Population
- `state_viewer.gd`：状态观察器

**违宪红线：**  
- Debug 内部“猜结构”（扫描 group 并推断谁是当前层）应逐步收敛为：只读 WorldRoot 提供的权威引用/映射（宪法 4.1）。

---

### 2.7 `autoload/`（全局只读工具或事件）
对应宪法：**3（黑盒）**

- `event_bus.gd`：事件总线（建议只做发布/订阅，不写规则）
- `registries.gd`：注册表（资源/ID 映射，便于解耦）
- `game_log.gd`：日志

---

## 3) 当前阶段的“合规结论”
- **主干合规**：Intent→Applied 管线 + 黑盒模块 + 只读 Debug 均已形成。
- **需要注意的唯一高风险点**：DebugOverlay/个别模块不要承担“世界结构推断”，应由 WorldRoot/Registry 输出权威指针或映射（宪法 4、5）。

---

## 4) 建议的仓库卫生（不影响架构，但建议做）
- 清理 `*.tmp`：避免 repo 噪音与误提交（尤其是 tscn 临时文件）。
- README 增加“数据流图 + 模块职责列表”（可从本文件提炼）。

