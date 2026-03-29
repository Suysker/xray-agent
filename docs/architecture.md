# architecture

- `install.sh` 只保留入口、菜单、参数路由、`RenewTLS` 兼容入口。
- `lib/` 是运行时真源，按 `common/runtime/system/tls/core/nginx/protocols/accounts/routing/features/apps/external/experimental` 分层。
- `templates/xray` 收口到 `base`、`inbounds`、`outbounds`、`extras`，Nginx 模板在 `templates/nginx`，分享链接模板在 `templates/share`。
- `profiles/` 使用 shell `key=value` 的 `.profile` 文件，分为 `install`、`protocol`、`routing`、`experimental`。
- `profiles/install/*.profile` 的 `protocols=` 直接驱动 `lib/protocols/compose.sh` 的 inbound 渲染顺序；`steps=` 负责安装流水线调度；`entry=` 只保留旧命令兼容。
- `verify/` 负责语法、协议渲染、路由修改、分享链接导出校验。
- `packaging/` 负责将仓库布局铺设到 `/etc/xray-agent`，并清理旧平铺文件与旧 profile/template 命名。
