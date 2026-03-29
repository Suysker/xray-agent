# legacy-diffs

- 原平铺 `lib/*.sh` 已移除，真实实现全部迁入分层目录。
- 原环境变量式 profile 已由 `*.profile` 取代，协议、安装组合、路由和实验能力都只读新 profile 树。
- 原平铺 Xray 模板已收口到 `base`、`inbounds`、`outbounds`、`extras` 四层目录。
- 菜单行为保持兼容，但 `install.sh` 不再内嵌外部工具实现。

- 以 master/install.sh 为行为基准
- 新结构以分层模块为唯一实现源
- 目录重构不代表删减原有协议与菜单能力
