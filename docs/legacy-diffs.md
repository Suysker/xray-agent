# legacy-diffs

- 原碎片化 `lib/<domain>/*.sh` 已移除，真实实现全部收口到领域级 `lib/*.sh`。
- 原环境变量式 profile 已由 `*.profile` 取代，协议、安装组合、路由只读新 profile 树。
- 原平铺 Xray 模板已收口到 `base`、`inbounds`、`outbounds`、`extras`；Nginx、分享链接和 systemd 保持模板化。
- 过度拆分的 tiny tpl 已移除；cron 行、包源行、fallback、routing rule、headers、sniffing、sockopt 等原子级配置由领域代码生成。
- 菜单行为保持兼容，但 `install.sh` 不再内嵌外部工具实现。

- 以 master/install.sh 为行为基准
- 新结构以领域级模块为唯一实现源
- 非本仓库 master 主线的 experimental、native TUN、native Hysteria2 不参与默认入口和验收
