# architecture

- `install.sh` 只保留 bootstrap、入口、菜单 1-23、参数路由、`RenewTLS` 兼容入口。
- `lib/` 是运行时真源，按领域级文件收口为 `common.sh`、`runtime.sh`、`system.sh`、`tls.sh`、`core.sh`、`nginx.sh`、`protocols.sh`、`accounts.sh`、`routing.sh`、`features.sh`、`apps.sh`、`external.sh`。
- `templates/` 只承载完整配置文件、重要配置块和稳定外部格式：Xray 在 `templates/xray`，Nginx 在 `templates/nginx`，分享链接在 `templates/share`，systemd unit 在 `templates/systemd`。
- 原子级配置不进模板目录：`[]`、fallback、routing rule、headers、sniffing、sockopt、cron 行、包源行都由领域代码中的命名函数生成。
- `profiles/` 使用 shell `key=value` 的 `.profile` 文件；主线配置只依赖 `install`、`protocol`、`routing`。
- `profiles/install/*.profile` 的 `protocols=` 直接驱动 `lib/protocols.sh` 的 inbound 渲染顺序；`steps=` 负责安装流水线调度；`entry=` 只保留旧命令兼容。
- 仓库不保留 `verify/` 或 `scripts/check.sh`；验证通过 README 中的手工命令和临时模板渲染完成。
- `packaging/` 负责将仓库布局铺设到 `/etc/xray-agent`，并清理旧小模块目录、旧 profile/template 命名、过度拆分的 tiny tpl、旧运行时 `verify/` 和 `scripts/`。
- 兼容基线是本仓库 `master:install.sh`，不引入 upstream/v2ray-agent 的 sing-box、订阅、anytls 等非主线能力。
