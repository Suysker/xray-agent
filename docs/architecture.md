# architecture

- `install.sh` 只保留 bootstrap、布局检查、模块加载和 `xray_agent_main` 调用。
- `lib/cli.sh` 承载菜单 1-23、参数路由和 `RenewTLS` 兼容入口；菜单只调度 workflow，不直接拼配置。
- `lib/installer.sh` 承载 install profile 加载、必填字段校验、安装 step dispatch、TLS/Reality 套餐编排。
- `lib/protocols.sh` 只负责 protocol profile、客户端 JSON、Xray inbound 与分享链接相关渲染。
- `lib/runtime.sh` 负责系统检测、安装状态检测、协议状态检测，并集中从现有 Xray/Nginx 配置反推 domain/path/UUID/端口/Reality 信息；不新增 state.json。
- `lib/` 是运行时真源，按领域级文件收口为 `common.sh`、`runtime.sh`、`system.sh`、`tls.sh`、`core.sh`、`nginx.sh`、`protocols.sh`、`installer.sh`、`cli.sh`、`accounts.sh`、`routing.sh`、`features.sh`、`apps.sh`、`external.sh`。
- `templates/` 只承载完整配置文件、重要配置块和稳定外部格式：Xray 在 `templates/xray`，Nginx 在 `templates/nginx`，分享链接在 `templates/share`，systemd unit 在 `templates/systemd`。
- 原子级配置不进模板目录：`[]`、fallback、routing rule、headers、sniffing、sockopt、cron 行、包源行都由领域代码中的命名函数生成。
- `profiles/` 使用 shell `key=value` 的 `.profile` 文件；主线配置只依赖 `install`、`protocol`、`routing`。
- `profiles/install/*.profile` 的 `protocols=` 直接驱动 `lib/installer.sh` 的 inbound 渲染顺序；`steps=` 负责安装流水线调度；`entry=` 只保留旧命令兼容。
- Xray 配置和分享协议以 `Xray-core` 当前源码为硬约束，官方 discussion/issue 用于判断推荐实践；旧 `install.sh` 只作为用户可见兼容基线，不作为配置正确性的唯一依据。
- 仓库不保留 `verify/` 或 `scripts/check.sh`；验证通过 README 中的手工命令和临时模板渲染完成。
- `packaging/` 负责将仓库布局铺设到 `/etc/xray-agent`，并清理旧小模块目录、旧 profile/template 命名、过度拆分的 tiny tpl、旧运行时 `verify/` 和 `scripts/`。
- 兼容基线是本仓库 `master:install.sh`，不引入 upstream/v2ray-agent 的 sing-box、订阅、anytls 等非主线能力。
