# xray-agent

xray-agent 是一个围绕 Xray-core 的安装与配置脚本，目标是把 master 分支的单文件安装脚本升级成“可持续演进的 Xray profile 构建器”，同时保持原版安装能力不丢失。

## 当前重点

- 只支持 [Xray-core](https://github.com/XTLS/Xray-core)
- 推荐组合聚焦在 VLESS + Vision / REALITY / XHTTP
- 保留原版 master 的 TLS 套餐、WS/VMess、共端口、伪装站、多用户、端口管理、证书管理、WARP/IPv6 分流、日志与路由工具
- 已引入 `lib/`、`templates/`、`profiles/` 目录，用于承接原单文件脚本的全部能力

## 支持矩阵

| 模式 | 状态 | 说明 |
| --- | --- | --- |
| VLESS + TCP + TLS + Vision | 推荐 | 核心稳定 profile |
| VLESS + TCP + REALITY + Vision | 推荐 | 当前主力 profile |
| VLESS + XHTTP + TLS | 推荐 | 已开始按 profile 导出分享链接 |
| VLESS + XHTTP + REALITY | 推荐 | 已开始按 profile 导出分享链接 |
| VLESS + WS + TLS | Stable | TLS 套餐内保留，与 master 保持兼容 |
| VMess + WS + TLS | Stable | TLS 套餐内保留，与 master 保持兼容 |
| Hysteria2 | Experimental | 已接入原生 profile 渲染 |
| local_tun | Experimental | 本地模式，独立于 VPS 服务端主流程 |

## 仓库结构

```bash
xray-agent/
├── install.sh
├── lib/
├── profiles/
├── templates/
└── docs/
```

- `install.sh` 继续承载现有安装流程，并开始读取共享常量与 profile 定义
- `lib/common.sh` 放置项目常量与通用编码能力
- `lib/env.sh` 统一仓库级目录变量
- `lib/profiles.sh` 负责读取 profile 定义并生成统一的 VLESS 导出链接
- `profiles/` 既定义核心 profile，也保留 WS/VMess 等 legacy profile
- `templates/` 承载 Vision / Reality / XHTTP / WS / VMess / Hysteria2 / TUN 模板
- `docs/` 已补充迁移、矩阵、profile、实验功能和本地模式说明

## 新菜单

- `模块化 Profile 菜单`：统一入口管理核心 profile，并保留 TLS 套餐中的 WS/VMess 兼容链
- `本地模式菜单`：生成 `local_tun` 配置并显示 Browser Dialer 说明
- `实验特性开关`：管理 Finalmask、ECH、VLESS Encryption、browser headers、trustedXForwardedFor

## 实验能力

- feature flag 持久化在 `/etc/xray-agent/feature-flags.env`
- 默认不开启 Finalmask、ECH、VLESS Encryption
- XHTTP 会默认带浏览器化 headers 模板

## 注意事项

- Cloudflare 请将 `SSL/TLS -> Overview` 设置为 `Full`
- 建议使用纯净系统，不支持非 root 账户
- 如系统已有自编译 Nginx 或其它代理脚本，建议清理后再执行安装
- CentOS 及低版本系统兼容性较弱，优先建议 Debian / Ubuntu
- Oracle Cloud 需要额外配置安全组或防火墙规则
- gRPC / HTTPUpgrade 不再作为后续增强重点，但原版已支持的主线能力继续保留

## 安装

- 安装完成后可使用 `vasma` 再次打开脚本
- 默认安装路径为 `/etc/xray-agent/install.sh`

```bash
wget -P /root -N --no-check-certificate "https://raw.githubusercontent.com/Suysker/xray-agent/master/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

## 许可证

[AGPL-3.0](https://github.com/Suysker/xray-agent/blob/master/LICENSE)
