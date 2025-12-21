# TEMPLATE_EXPORT.md
> 用于把 7-world 抽成“可复用模板”的导出清单（建议提交到 docs/）

## 1. 推荐可复用目录
- `res://core/`（WorldState、LayerBase/LayerState、InertiaField 等）
- `res://debug/`（DebugOverlay）
- `res://ecology/`（只保留接口与示例规则，业务规则可替换）

## 2. 推荐项目专用目录（不建议复用）
- `res://layers/`（具体层内容、资源、场景）
- `res://assets/`（美术/音频）
- `res://content/`（关卡/剧情/配置，若有）

## 3. 导出方式（两种）
### A. 复制粘贴导出
- 新项目创建同样目录结构
- 复制 core/debug/ecology 框架文件
- 删除或替换 ecology 里具体规则

### B. 模板仓库导出（长期）
- 把框架目录独立成仓库 `godot-systems-template`
- 新项目从 template 初始化（GitHub template repo）
- 业务代码作为子目录或子模块

## 4. 最小启动验证（模板自检）
- DebugOverlay 能显示 WorldState
- 至少一个 LayerBase 能跑通 intent->applied
- 一个 Consumer（Spawner）能读取 applied 并可观测变化
