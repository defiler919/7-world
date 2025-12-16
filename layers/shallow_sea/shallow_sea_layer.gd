extends Node2D 
# 模块：layers/shallow_sea/shallow_sea_layer.gd
# 职责：浅海层容器：承载本层内容并输出本层状态（LayerState）。
# 输入：本层配置、生态“建议值”、时间。
# 输出：LayerState（繁荣/多样性等）。
# 禁止：
# - 直接访问其他层节点
# - 硬编码跨层逻辑
