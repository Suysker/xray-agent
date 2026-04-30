# menu-map

- `1` -> `lib/cli.sh` -> `profiles/install/tls_vision_xhttp.profile` -> `lib/installer.sh`
- `2` -> `lib/cli.sh` -> `profiles/install/reality_vision_xhttp.profile` -> `lib/installer.sh`
- `3` -> `lib/accounts.sh`
- `4` -> `lib/nginx.sh`
- `5` -> `lib/tls.sh`
- `6~8` -> `lib/routing.sh`
- `9~11`、`14~16` -> `lib/features.sh`
- `12` -> `lib/protocols.sh` -> Xray-core Hysteria2 管理，显示在工具管理分组
- `13` -> `lib/core.sh`
- `17` -> `lib/apps.sh`
- `18~23` -> `lib/external.sh`

默认入口只暴露 1-23 项菜单。菜单能力保持本仓库 `master:install.sh` 兼容，编号按当前显示顺序从上到下连续排列；Hysteria2 是内置协议管理，不属于其他功能或外部脚本。

菜单 3-12 属于核心控制台，进入后都会先展示统一状态头。证书菜单使用智能申请向导；账号、伪装站、路由、端口、嗅探、sockopt、Hysteria2 菜单会展示当前状态和影响范围，再执行写入操作。
