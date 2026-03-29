# xray-agent

xray-agent 已从单文件安装脚本收口为一套模块化的 Xray profile builder。当前入口仍然是 `install.sh`，但真实实现已经拆到 `lib/`、`profiles/`、`templates/`、`verify/` 和 `packaging/`。

## 当前状态

- 保留 master `install.sh` 的菜单编号、`RenewTLS` 兼容入口、TLS/Reality 套餐、多用户、WARP/IPv6/黑名单、日志、证书、伪装站、外部工具菜单。
- 运行时只加载分层模块，不再依赖旧平铺 `lib/*.sh`、旧 `profiles/*.env`、旧平铺模板。
- 协议渲染、安装组合、分享链接导出统一从 `profiles/*.profile` 和 `templates/` 读取。

## 目录

```text
xray-agent/
├── install.sh
├── lib/
├── templates/
├── profiles/
├── docs/
├── verify/
└── packaging/
```

- `install.sh`：入口、菜单、参数路由、旧命令兼容。
- `lib/`：按 common/runtime/system/tls/core/nginx/protocols/accounts/routing/features/apps/external/experimental 分层。
- `templates/`：Xray、Nginx、分享链接模板。
- `profiles/`：安装组合、协议、路由、实验特性描述。
- `verify/`：语法、渲染、路由、分享链接校验。
- `packaging/`：安装布局、升级迁移、卸载辅助。

## 安装

```bash
wget -P /root -N --no-check-certificate "https://raw.githubusercontent.com/Suysker/xray-agent/master/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

- 安装后入口为 `/etc/xray-agent/install.sh`
- 快捷方式仍为 `vasma`

## 验证

```bash
bash verify/smoke.sh
bash verify/render-protocols.sh
bash verify/routing-check.sh
bash verify/share-link-check.sh
```

## 文档

- 架构说明见 `docs/architecture.md`
- 旧函数到新模块映射见 `docs/parity-matrix.md`
- 迁移与回滚见 `docs/migration-plan.md`
