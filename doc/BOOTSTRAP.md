# BOOTSTRAP.md — 世界启动与入口冻结说明

> 本文档用于明确 7-world 的**唯一启动路径**，  
> 防止世界状态在多个地方被修改，导致结构失控。

---

## 1. 主场景（唯一入口）

- 主场景文件：
  - `main.tscn`
- 所有游戏运行，必须从该场景启动
- 禁止从任意 Layer / Debug / Test 场景直接运行完整世界

---

## 2. 世界中枢（World Root）

- 世界中枢节点：
  - 节点名：`WorldRoot`
  - 脚本：`core/world/world_root.gd`

### WorldRoot 的唯一职责：
- 统一更新 `WorldState`
- 维护当前层 / 列 / 世界时间
- 作为世界结构的“唯一权威”

### 明确禁止：
- ❌ 任何其他节点直接写 WorldState
- ❌ Layer / Debug / Visuals 控制世界切换

---

## 3. 生态系统入口（Ecology）

- 生态规则节点：
  - `EcologyRules`
  - 脚本：`ecology/ecology_rules.gd`

### 规则：
- Ecology 只产出 Intent
- 不生成实体、不修改世界、不做视觉

---

## 4. 层系统（Layers）

- 所有层节点必须：
  - 继承 `LayerBase`
  - 加入 group：`layers`
  - 作为 WorldRoot 的子节点或受其管理

### 层职责：
- 拉取 Intent
- 通过惯性生成 Applied
- 维护 LayerState

---

## 5. 子模块加载规则

- Spawner / Visuals / Vignette / Hazard：
  - 必须作为 Layer 的子节点
  - 只读 `layer.state.applied`

---

## 6. Debug 系统

- DebugOverlay：
  - 只读 WorldRoot / WorldState / LayerState
  - 禁止直接查找并解释世界结构

---

## 7. 启动路径总结（一句话）

**main.tscn → WorldRoot → EcologyRules → LayerBase → 子模块 → Debug**

这是唯一允许的世界启动与运行路径。


## Project Status

As of 2025-12-22:
- Core world architecture is frozen
- Ecology system is stable and non-apocalyptic by design
- Future gameplay must be introduced via event systems only
