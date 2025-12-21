# MODULE_CONTRACTS.md — 关键模块契约（输入/输出/禁止事项）

> 目标：给 AI（以及未来的你）一个“可安全扩展”的边界清单。  
> 规则：每个模块都写清 **输入、输出、读写、禁止事项**，避免职责漂移。

---

## 1) core/world/world_root.gd — WorldRoot（世界中枢）

**职责**  
- 统一更新 `WorldState`（世界快照：layer/col/time/camera/viewport/cooldown…）  
- 作为“结构权威”：提供当前层/层列表/映射（建议未来统一从这里出）

**输入（只读）**  
- `WorldClock` / 时间 tick（若由 time 模块提供）  
- 输入系统（切层/切列）产生的请求（若存在）

**输出（写入）**  
- 写 `WorldState`（唯一写入者）  
- 对外提供只读接口：`get_world_state()` / `get_current_layer()` / `get_layers()`（推荐）

**禁止事项**  
- ❌ 不在这里写生态规则（生态只在 ecology）  
- ❌ 不直接操作层内实体（那是 spawner 的事）

---

## 2) core/world/world_state.gd — WorldState（世界快照）

**职责**  
- 保存“世界现在是什么样”（只读快照）

**输入/输出**  
- 输入：由 WorldRoot 写入  
- 输出：所有系统可读取

**禁止事项**  
- ❌ 禁止任何玩法规则/分支  
- ❌ 禁止驱动相机/生成/生态

---

## 3) core/layer/layer_base.gd — LayerBase（层基类）

**职责**  
- 每帧管线：`Intent -> Flatten -> InertiaField -> Applied -> LayerState`

**输入（只读）**  
- `get_layer_intent()`（由子类实现，通常从 EcologyRules 读取）

**输出（写入）**  
- 写 `LayerState`（intent/applied/taus/dt…）

**关键接口**  
- `get_layer_intent() -> Dictionary`（子类必须提供）  
- `_tau_for_key(key:String)->float`（子类可按 key 前缀分层 tau）  
- `_after_state_updated(state)`（扩展点，默认空）

**禁止事项**  
- ❌ 不生成实体  
- ❌ 不改相机/世界结构  
- ❌ 不写生态规则

---

## 4) core/layer/inertia_field.gd — InertiaField（惯性字段）

**职责**  
- 维护 key->current、key->tau、key->max_rate  
- 提供 `step(key, target, dt, tau)` 输出下一帧值

**输入**  
- key、target、dt、tau  
- 可选：max_rate

**输出**  
- next_value（float）

**禁止事项**  
- ❌ 不依赖任何节点/世界结构

---

## 5) core/layer/layer_state.gd — LayerState（层快照）

**职责**  
- 保存层级快照：intent/applied/taus/dt/name…

**禁止事项**  
- ❌ 不写规则，不做决策

---

## 6) ecology/ecology_rules.gd — EcologyRules（生态规则汇总）

**职责**  
- 只产 Intent：`get_layer_intent(layer_index)` 或等价接口  
- 汇总 prosperity/diversity/invasion 等子规则

**输入（只读）**  
- 世界时间（world_time）  
- 可选：历史生态态（ecology_layer_state）

**输出（只写 Intent）**  
- 返回 Dictionary（树形/层级键）

**禁止事项**  
- ❌ 不生成实体、不改视觉、不改相机  
- ❌ 不写 LayerState（LayerState 由 LayerBase 写）

---

## 7) layers/*/*_layer.gd — Shallow/Deep Layer（具体层）

**职责**  
- 作为 LayerBase 子类：  
  - 拉取对应层的 intent  
  - 定义 tau 分层策略（按 key 前缀：spawn/death/budget/hazard…）

**输入（只读）**  
- EcologyRules.get_layer_intent(layer_index) 或同等接口

**输出**  
- 通过父类写 LayerState

**禁止事项**  
- ❌ 不把 spawner/visuals 写进这里（应作为子节点黑盒模块）

---

## 8) layers/common/layer_spawner.gd — LayerSpawner（生成黑盒）

**职责**  
- 只读 `layer.state.applied`，生成/回收实体  
- 维护内部计数与引用清理  
- 对外提供 `get_population_state()`

**输入（只读）**  
- `budget.spawn_points`（承载/总量）  
- `spawn.fish_bias / spawn.algae_bias`（比例）  
- `death.fish_bias`（死亡强度）

**输出（行为）**  
- instantiate fish/algae  
- queue_free 回收/死亡  
- `get_population_state()` 返回统计

**禁止事项**  
- ❌ 不写 intent/applied  
- ❌ 不访问 WorldRoot 来做决策（只做层内行为）

---

## 9) layers/common/layer_visuals.gd — LayerVisuals（层视觉黑盒）

**职责**  
- 只读 `layer.state.applied` 做背景/色调/亮度等渐变

**输入（只读）**  
- 例如：`env.pollution`、`invasion.risk` 等（以你实际使用为准）

**输出（行为）**  
- 改材质参数/ColorRect/背景色（仅表现）

**禁止事项**  
- ❌ 不写规则、不生成实体

---

## 10) layers/common/layer_warning_vignette.gd — WarningVignette（暗角压迫）

**职责**  
- 用风险值驱动 vignette alpha（建议带 enabled + fade-out）

**输入（只读）**  
- `invasion.risk`（或 hazard 输出的风险字段）

**输出（行为）**  
- ColorRect alpha / shader 参数

**禁止事项**  
- ❌ 不参与生态决策  
- ❌ 不写 state

---

## 11) layers/common/layer_hazard.gd — LayerHazard（危险/入侵桥）

**职责（推荐定位）**  
- 作为“层内危险态聚合器”：从 applied 计算一些“表现/局部系统需要的危险态”  
- 或者仅作为桥接，把 applied 的 hazard.* 规范化输出

**输入（只读）**  
- `hazard.*`、`invasion.risk` 等

**输出（只读快照或信号）**  
- `get_hazard_state()` 或内部缓存供 visuals/vignette 读取（可选）

**禁止事项**  
- ❌ 不生成实体  
- ❌ 不写生态规则

---

## 12) debug/debug_overlay.gd — DebugOverlay（只读 HUD）

**职责**  
- 每帧读取 WorldRoot.get_world_state()  
- 显示：世界、生态 intent、层 applied、population 等

**输入（只读）**  
- `WorldState`  
- `EcologyRules`（只读）  
- `Spawner.get_population_state()`（只读）

**禁止事项（高优先级）**  
- ❌ 不要扫描 group 来“猜当前层”  
- ✅ 应从 WorldRoot 获得“当前层权威引用/映射”（未来收口点）

---

## 13) debug/state_viewer.gd — StateViewer（只读状态面板）
同 DebugOverlay：只读展示，不参与逻辑。

---

## 14) presentation/* — 表现映射层（世界级美术逻辑）
**职责**  
- 状态→表现（可读 WorldState/LayerState）  
- 稀有现象/氛围变化如果是“表现”，不要写“规则触发”

**禁止事项**  
- ❌ 不做生态决策、不改实体生成

