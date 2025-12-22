# 7-world · Documentation Index
（宪法 / 架构 / 系统规范总导航）

> 本目录用于**防止项目跑偏**。  
> 任何新系统、新机制、新代码，在加入前都应先对照相关宪法与规范。  
> 当行为与文档冲突时，以文档为准。

---

## 一、总宪法（最高优先级）

### 1️⃣ 项目总宪法
📄 **CONSTITUTION_7-world.md**

- 定义项目的最高设计原则
- 模块边界、只读/可写规则
- 世界观与工程观的统一
- 所有系统的最终裁决依据

> 👉 如果只读一份文档，请读这一份。

---

## 二、整体架构与工程设计

### 2️⃣ 架构总览
📄 **ARCHITECTURE_MAP.md**

- 世界整体技术结构图
- WorldRoot / WorldState / Layer / System 的关系
- 数据流方向（只读 vs 写入）
- “谁能改谁”的明确边界

---

### 3️⃣ 可移植架构说明
📄 **PORTABLE_ARCHITECTURE.md**

- 哪些模块是“可直接带走复用的”
- 哪些是项目特化的
- 如何把 7-world 当成下一个项目的骨架

> 👉 面向未来项目的文档。

---

### 4️⃣ 世界层级与变化规则
📄 **WORLD_CHANGE_LAYERS.md**

- 层级（Layer）如何定义与切换
- layer_id / layer_index 的使用原则
- 世界变化如何跨层传播
- 为什么不直接依赖 index

---

## 三、模块级宪法（系统合同）

### 5️⃣ 模块合同清单
📄 **MODULE_CONTRACTS.md**

- 每个核心模块的职责
- 输入 / 输出 / 禁止行为
- Debug / State / Logic 的边界
- 用于防止模块互相污染

---

## 四、系统接入与扩展规范

### 6️⃣ 事件系统宪法（Event System）
📄 **EVENT_SYSTEM_CONSTITUTION.md**

- 什么是“事件”，什么不是
- 事件生命周期
- 调度、冷却、并发限制
- 非末日（Non-Apocalypse）条款
- 事件如何影响生态而不破坏生态

> 👉 所有危机、扰动、特殊情况，必须通过事件系统接入。

---

## 五、工程启动与当前状态

### 7️⃣ 项目启动说明
📄 **BOOTSTRAP.md**

- 当前工程状态
- 已冻结系统列表
- 合法扩展入口
- 给“未来的你 / 合作者”的说明

---

### 8️⃣ README（项目入口）
📄 **README.md**

- 项目简介
- 当前目标
- 运行方式
- 文档入口指引

---

## 六、阅读建议（给未来的你）

### 🔰 新加入项目 / 久未回归
阅读顺序：
1. CONSTITUTION_7-world.md
2. ARCHITECTURE_MAP.md
3. BOOTSTRAP.md
4. EVENT_SYSTEM_CONSTITUTION.md

### 🧠 想加新系统
阅读顺序：
1. CONSTITUTION_7-world.md
2. MODULE_CONTRACTS.md
3. EVENT_SYSTEM_CONSTITUTION.md
4. PORTABLE_ARCHITECTURE.md

---

## 七、规则声明（非常重要）

- 文档不是注释，而是**工程约束**
- 代码可以改，宪法不能随便改
- 若代码与宪法冲突：
  - 要么回滚代码
  - 要么升级宪法（并记录变更原因）

---

_Last updated: 2025-12-22_
