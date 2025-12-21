# PORTABLE_ARCHITECTURE.md
> 你从 7-world 项目里“能带走什么”：可复用架构与宪法清单（跨项目可复制粘贴）

## 1) 你真正获得的“可复用资产”
这次项目最有价值的不是某个脚本，而是 **一套可复制的工程组织方式**：

### A. 宪法体系（最可复用）
- 模块宪法（每个模块：职责/输入/输出/禁止项）
- 世界变化分层白名单（Field / Modulator / Event / Milestone）
- 数据流宪法：`Rules -> Intent -> Inertia -> Applied -> State -> Consumers`
- 黑盒原则：模块只读外部；对外只暴露接口；不依赖节点路径（或只注入 NodePath）

> 复用方式：把 docs/ 下宪法文件直接复制到新项目，改名/删改内容即可。

### B. 通用“系统骨架”（可直接搬走）
- `WorldState`：世界快照（只读、统一解释）
- `DebugOverlay`：只读仪表盘（观察所有系统）
- `Rules/Intent`：规则引擎输出建议参数（纯数据）
- `InertiaField`：对 key 分层惯性（tau / max_rate）
- `LayerBase/LayerState`：每层通用管线（intent->applied->state）
- `Spawner/Consumers`：只读 state.applied 的执行器（实体生成/回收/表现）

> 复用方式：把 core/ debug/ ecology/ layer/ 这些“框架目录”打包成模板仓库。

### C. 事件系统“接入方式”（未来价值最大）
- 事件定义 Resource（.tres 数据驱动）
- 事件运行态 Runtime（剩余时间/冷却/种子/绑定层）
- Policy（运行策略：一层最多一个 crisis，但结构支持并发）
- Bus/Contributor（任何新系统都能“投递修正”而不改老代码）

> 复用方式：以后任何项目新增系统，只需要实现 Contributor 接口即可接入生态/世界。

---

## 2) 你下一个项目可以怎么“直接复用”
给你三种复用级别（由轻到重）：

### 级别 1：只复用宪法（最快）
适用：你只想保持“不会跑偏”的开发纪律  
做法：
- 复制 docs/CONSTITUTION*.md + WORLD_CHANGE_LAYERS.md
- 在新项目里照着写每个模块的宪法
- DebugOverlay 先搭起来，保证可观测性

### 级别 2：复用框架骨架（推荐）
适用：你还想继续做“系统驱动/模拟驱动”的项目  
做法：
- 复制 `core/world_state.gd`、`debug/debug_overlay.gd`
- 复制 `core/layer/layer_base.gd`、`core/layer/layer_state.gd`
- 复制 `core/inertia/inertia_field.gd`（或你项目现有位置）
- 复制 `ecology/ecology_rules.gd`（改成新项目规则）
- 新项目只写：新的 Rules、新的 Consumers

### 级别 3：做成模板仓库（长期收益最高）
适用：你以后会连续启动多个项目  
做法：
- 把“骨架目录”抽到一个 `godot-systems-template` 仓库
- 每次新项目用 template 仓库初始化
- 业务代码写在 `game/` 或 `content/` 下，框架代码在 `core/` 下

---

## 3) “可复用”的关键不是搬文件，而是搬边界
你要带走的最重要边界：

1. **状态与行为分离**
- `WorldState` / `LayerState` = 状态（只读快照）
- `Rules`/`Intent` = 建议（只读）
- `Consumers` = 行为执行（读取 applied）

2. **总线接入（避免改老代码）**
- 新系统只贡献 `facts` 或 `modifiers`
- Rules 不需要知道“是谁贡献的”

3. **策略层（Policy）**
- 设计支持并发，运行用策略限制（例如每层只触发一个事件）
- Debug 可以放开并发用于测试

---

## 4) 建议你现在就做的“一次性整理”
为了让你未来能“直接拿走架子”，建议把当前项目再补 2 件事：

1) `docs/TEMPLATE_EXPORT.md`
- 记录哪些目录属于“框架可复用”，哪些属于“内容/项目专用”
- 列一个复制清单

2) `docs/INTERFACES.md`
- 明确列出对外接口：WorldRoot、EcologyRules、LayerBase、Spawner、DebugOverlay
- 每个接口写：输入/输出/禁止项（简短版）

这样你下一个项目开局会非常快。
