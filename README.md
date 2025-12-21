# 7-world

一个基于 Godot 的 **分层生态系统实验项目**。  
玩家/相机只是在“浏览世界”，而生态在后台以慢变量方式持续演化。

---

## 核心设计原则（一句话）
- 生态规则只产出 **Intent**
- 世界通过 **惯性系统** 平滑成 **Applied**
- 所有实体、视觉、风险只读 Applied
- 状态与行为严格分离
- 模块全部黑盒化、可插拔

---

## 主干数据流

WorldRoot
↓
WorldState（世界快照）
↓
EcologyRules → Intent
↓
LayerBase（惯性）
↓
LayerState.applied
↓
Spawner / Visuals / Vignette / Hazard


---

## 项目结构说明

请先阅读以下文档（按顺序）：

1. `docs/CONSTITUTION_7-world.md`  
   → 项目最高设计约束（不可违反）

2. `docs/ARCHITECTURE_MAP.md`  
   → 目录结构与模块归位

3. `docs/MODULE_CONTRACTS.md`  
   → 关键模块输入 / 输出 / 禁止事项

4. `docs/BOOTSTRAP.md`  
   → 世界启动与入口冻结说明

---

## 如何运行

- 使用 Godot 打开项目
- 运行主场景：`main.tscn`

---

## 状态说明

本项目当前处于：  
**v0.x · 世界生态闭环构建阶段**

功能在增加之前，优先保证结构稳定。
