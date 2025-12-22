# Event System Constitution（事件系统宪法）

> 目标：为“长期稳定运行的生态世界”提供可控、可扩展、可复用的事件机制。  
> 事件应当造成阶段性扰动与损失，并在事件结束后由系统自动回归到可持续的平衡区间。  
> 默认禁止“必然末日”演化（除非明确标记为剧情/挑战模式并默认关闭）。

---

## 0. 名词定义

### 事件（Event）
一次“有开始/过程/结束”的世界扰动，它可以：
- 临时改变某层的生态倾向（Intent）
- 临时施加风险/污染/预算等指标的偏移
- 造成实体损失（鱼减少、资源减少等）
- 触发视觉表现强度（vignette、颜色呼吸、告警等）

事件必须满足：
- **可开始**、**可更新**、**可结束**
- **可复现**（同 seed/同输入可重现）
- **可记录**（可写入存档）

### 状态（State）
- **WorldState**：世界快照（只读给 UI/Debug）
- **LayerState**：层快照（只读给 UI/Debug）
- **EcologyLayerState**：生态内部事实（由生态系统写入/维护）

### 意图（Intent）
生态系统输出的“建议值”字典（spawn/death/budget/invasion/env.pollution 等）。  
事件通常不直接改“最终执行结果”，而是：
- 注入 **Intent 修正（delta/modifier）**
- 或施加一次性 **事实冲击（shock）**
最终效果仍通过 `Intent -> Inertia -> Applied -> Consumers` 管道生效。

---

## 1. 设计目标

1. **长期稳定**：事件是扰动，不是终局。
2. **强可控**：运行时可配置“同层最多同时 1 个事件触发”。
3. **强扩展**：新增事件不改旧事件，不改核心生态公式结构。
4. **强可复用**：事件系统可搬到其他项目（不绑鱼/草具体实现）。
5. **可观察**：DebugOverlay 可看到当前事件、剩余时间、强度、影响项摘要。
6. **可存档**：事件运行态可保存/恢复（至少：id、layer_id、elapsed、duration、seed、cooldown）。

---

## 2. 系统边界（严禁越界）

### 2.1 事件系统负责
- 决定某层当前是否触发事件（调度）
- 更新事件进度（计时、阶段、强度曲线）
- 输出“事件影响”（对 intent 的偏移、或事实冲击）
- 提供可存档结构

### 2.2 事件系统不负责（写了就违规）
- ❌ 不直接控制相机/切层
- ❌ 不直接写 UI（只能输出事件状态供 UI 只读显示）
- ❌ 不直接写 DebugOverlay（DebugOverlay 只读）
- ❌ 不重写生态主循环结构（ecology_rules 的框架不得被事件侵入）
- ❌ 不硬编码 layer_index==0 这种业务逻辑（必须通过 layer_id 映射与配置）

---

## 3. 事件范围：包含什么/不包含什么

### 3.1 事件包含（离散发生、可结束的扰动）
- 入侵（Invasion）
- 疫病（Disease/Plague）
- 暴风（Storm）
- 缺氧（Hypoxia）
- 食物链冲击（FoodChainShock）
- 污染事故（AccidentPollution）
- 迁徙潮（MigrationWave）
- 临时丰收/补给（Bloom/Relief）

### 3.2 不属于事件（常态系统/连续系统）
- 昼夜（DayNight）→ Field（背景态）
- 天气循环（WeatherCycle）→ Field（背景态）
- 季节/气候趋势（Season/Climate）→ Field 或 Modulator

> 结论：  
> **昼夜/天气本体不是事件**；  
> 但“暴风雨来袭 30 秒”“极端寒流 45 秒”可以是事件。

---

## 4. 事件接口（最小标准）

每个事件（无论用 Script / Resource / 组合）必须有：

### 4.1 稳定身份
- `id: StringName`：稳定ID（存档/映射用，永不改语义）
- `category: StringName`：分类（例如 `crisis` / `ambient` / `story`）
- `scope_layer_id: StringName` 或 `scope_rule`：作用范围（绑定层或按规则选层）

### 4.2 运行态字段（Runtime）
- `layer_id: StringName`：实例绑定到哪一层（存档关键）
- `duration: float`
- `elapsed: float`
- `seed: int`
- `phase: StringName`（可选）

### 4.3 生命周期
- `start(ctx) -> void`
- `tick(ctx, dt) -> void`
- `end(ctx) -> void`
- `is_finished() -> bool`

### 4.4 输出（至少一种）
- **Intent 修正**：`get_intent_delta() -> Dictionary`
  - 返回形如 `{ "death.fish_bias": +0.2, "budget.spawn_points": -0.6 }`
- **事实冲击（可选、少用）**：`apply_shock(ctx) -> void`
  - 例如在 start 时一次性扣减 fish
- **表现提示（可选）**：`get_presentation() -> Dictionary`
  - `{ "vignette_intensity": 0.3, "alert_level": 1 }`

---

## 5. 调度规则（运行策略）

### 5.1 并发支持 vs 运行限制
- 架构上允许多个事件并发（为了扩展）
- 默认运行策略：**每层同一时刻最多 1 个 `crisis` 事件**
- 可扩展策略：
  - `max_crisis_per_layer = 1`
  - `max_ambient_per_layer = 0/1`（未来可开）
  - `max_total_events_per_layer = 1`（当前项目可直接用这个最保守）

### 5.2 冷却
每层维护：
- `cooldown_left`
- `last_event_id`
- `last_event_end_time`

规则：
- 事件结束后进入冷却期
- 冷却期内不触发新事件
- 冷却长度可配置（按层/按事件）

### 5.3 触发依据
触发必须满足：
- 条件判断只读 `WorldState/LayerState/EcologyLayerState`
- 触发概率可配置：`base_chance + f(modulators, fields, layer_state)`
- 不允许把触发逻辑散落在多个系统里（统一由 scheduler 决定）

---

## 6. 稳定性条款（Non-Apocalypse 默认条款）

默认模式：**Non-Apocalypse（非末日）**

必须满足：
1. 事件结束后存在回归机制（恢复/繁殖/补偿/净化）
2. 关键基础资源不得被永久清零（除非显式 story/challenge）
3. 风险/污染必须存在回落通道（可慢但必须存在）
4. 任何“持续增长且无上限”的指标必须有：
   - clamp 上限 或
   - 软上限（增长趋缓）+ 回落机制

如果某事件会导致不可逆崩盘，必须：
- 标记 `category = story` 或 `mode = apocalypse`
- 默认不启用（需要显式开启）

---

## 7. 数据驱动与扩展方式

新增事件必须满足：
- 不修改旧事件代码
- 不修改 WorldRoot/WorldState 的语义
- 不修改 ecology_rules 的结构（允许新增 intent key，但要登记）

推荐：
- 事件定义使用 `.tres Resource`（参数化）
- 统一通过 `EventRegistry` 注册
- 运行态由 `EventScheduler/EventRunner` 管理

---

## 8. 可观测性（Debug & 日志）

必须提供 Debug 字段（最少）：
- 当前层 active_event_id（无则 `none`）
- `time_left` / `elapsed` / `duration`
- `intensity`（0..1，可选）
- 影响项摘要（最多列 5 个关键 key）

DebugOverlay 只读这些字段，不参与计算。

---

## 9. 存档条款

存档必须包含：
- `current_layer_id`（世界当前激活层）
- 每层：
  - `active_event_id`
  - `elapsed`
  - `duration`
  - `seed`
  - `cooldown_left`
  - `category`（可选）

兼容性：
- 新增字段不应破坏旧档读取（默认值兜底）

---

## 10. 典型违规反例（出现即回退）

- 在事件里直接 `get_node("Fish").queue_free()` 批量清空实体
- 在事件里直接改 `WorldState.current_layer_index` 或相机
- 在事件里直接改 DebugOverlay 文本
- 在事件里重写生态主循环、改变 Intent 管道结构
- 用 `if layer_index == 0` 写死浅海逻辑（必须走 layer_id 映射/配置）
