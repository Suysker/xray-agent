# xray-agent

xray-agent 已从单文件安装脚本收口为一套模块化的 Xray profile builder。`install.sh` 只负责 bootstrap 和加载主入口，真实实现收敛在 `lib/*.sh` 领域模块、`profiles/`、`templates/` 和 `packaging/`。

## 当前状态

- 以本仓库 `master:install.sh` 为兼容基线，保留菜单 1-23、`RenewTLS` 兼容入口、TLS/Reality 套餐、多用户、WARP/IPv6/黑名单、日志、证书、伪装站、外部工具菜单；Hysteria2 已收口为工具管理里的 Xray-core 内置协议管理。
- 运行时只加载领域级 `lib/*.sh` 模块，不再保留旧碎片化 `lib/<domain>/*.sh`、旧 `profiles/*.env`、旧平铺模板。
- CLI、安装编排、协议渲染已经分层：`cli.sh` 管菜单和参数路由，`installer.sh` 管 install profile 和安装流水线，`protocols.sh` 只管协议 profile 与配置渲染。
- 协议渲染、安装组合、分享链接导出统一从 `profiles/*.profile` 和重要配置模板读取；一行默认值、小 JSON 片段、cron 行和包源行由领域代码生成。
- Xray 配置与分享链接按 Xray-core 源码优先审计：Reality 服务端配置不写客户端 `publicKey`，XHTTP 默认只写必要 `path`，Hysteria2 使用 Xray-core `hysteria` inbound 和 `finalmask.quicParams`，分享 URI 按官方约定编码。
- install profile 的 `protocols=` 直接决定 TLS/Reality 套餐渲染哪些 inbound；TLS 套餐默认包含 `VLESS-TCP / VLESS-WS / VMess-WS / XHTTP / Hysteria2`；Reality 套餐安装时可选择同时启用 Hysteria2，默认不强制开启；`steps=` 进一步决定安装流水线顺序。
- Hysteria2 的连接域名/SNI/证书域名默认复用当前 `domain`/`TLSDomain`，不使用 Reality 目标域名签证书；masquerade 默认优先复用已有 Hy2 配置，其次复用 Nginx 伪装站 upstream，Reality-only 场景再把 Reality 目标域名作为内容源候选。
- 不引入 upstream/v2ray-agent 的 sing-box、订阅、anytls 等非本仓库 master 主线能力。

## 目录

```text
xray-agent/
├── install.sh
├── lib/
├── templates/
├── profiles/
├── docs/
└── packaging/
```

- `install.sh`：bootstrap、模块加载、调用 `xray_agent_main`。
- `lib/`：领域级运行时模块，边界为 `common.sh`、`runtime.sh`、`system.sh`、`tls.sh`、`core.sh`、`nginx.sh`、`protocols.sh`、`installer.sh`、`cli.sh`、`accounts.sh`、`routing.sh`、`features.sh`、`apps.sh`、`external.sh`。
- `templates/`：只放完整配置文件、重要配置块和稳定外部格式，例如 Xray、Nginx、分享链接和 systemd；不为 `[]`、一行 rule、cron 行、包源行单独建模板。
- `profiles/`：安装组合、协议、路由描述。
- `packaging/`：安装布局、升级迁移、卸载辅助。

## 安装

```bash
wget -P /root -N --no-check-certificate "https://raw.githubusercontent.com/Suysker/xray-agent/master/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

- 首次只下载到单个 `install.sh` 时，它会自动下载仓库归档并铺设完整模块化布局。
- 安装后入口为 `/etc/xray-agent/install.sh`
- 快捷方式仍为 `vasma`

## 验证

仓库不保留一键验证脚本；改动后至少执行：

```bash
bash -n install.sh
find lib packaging -name "*.sh" -print0 | xargs -0 -n1 bash -n
bash -c 'source ./install.sh; declare -F xray_agent_main >/dev/null; declare -F menu >/dev/null; declare -F xray_agent_run_install_profile >/dev/null'
```

配置模板变更需要用临时目录手工渲染，并对生成的 Xray JSON 执行 `jq empty`。同时检查 `find templates -type f`，确认没有新增原子级 tiny tpl。

## 文档

- 架构说明见 `docs/architecture.md`
- 旧函数到新模块映射见 `docs/parity-matrix.md`
- Xray-core 官方源码审计说明见 `docs/official-xray-audit.md`
- 迁移与回滚见 `docs/migration-plan.md`
