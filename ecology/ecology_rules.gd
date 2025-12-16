extends RefCounted
# 模块：ecology/ecology_rules.gd
# 职责：计算演化倾向（繁荣/多样性驱动），输出“建议”，不直接改画面。
# 输入：LayerState/WorldState、时间。
# 输出：生成/繁殖/入侵等倾向参数（建议值）。
# 禁止：
# - 直接操作节点树/材质/相机
# - 直接生成实体（由 Layer 或 World 执行）
