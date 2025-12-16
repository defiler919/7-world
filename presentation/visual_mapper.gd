extends RefCounted
# 模块：presentation/visual_mapper.gd
# 职责：把“状态”映射为“表现参数”（只读状态）。
# 输入：WorldState/LayerState。
# 输出：氛围/光影/稀有表现的权重建议。
# 禁止：
# - 反向修改生态/世界状态
# - 直接增删实体
