# xray-agent

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)
[![Xray-core](https://img.shields.io/badge/Xray--core-supported-brightgreen.svg)](https://github.com/XTLS/Xray-core)
[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Linux-lightgrey.svg)](#系统要求)

xray-agent 是一个面向 Xray-core 的 N 合一安装与管理脚本，提供 TLS、Reality、XHTTP、Hysteria2、证书、账号、路由、WARP、Nginx 伪装站等常用能力。脚本保留简单的菜单体验，同时将 Xray、Nginx、systemd 和分享链接配置集中到模板与 profile 中，便于长期维护。

> 本项目仅供学习、研究和合法的网络管理用途。网络环境和审查策略会持续变化，任何工具都不能保证绝对可用或不可识别。本项目的目标是减少常见配置错误，并按 Xray-core 正式版能力降低明显指纹风险。

## 为什么选择 xray-agent

xray-agent 的目标不是把所有协议简单堆在一起，而是把常用的 Xray-core 能力做成一套可以长期维护的 N 合一控制台。你可以从同一个菜单完成安装、证书、账号、分享、伪装站、路由、WARP、Hysteria2、日志和内核管理，不需要在多个脚本、配置文件和外部项目之间来回切换。

- **一套入口管理多协议**：TLS 套餐默认提供 VLESS TCP Vision、VLESS WS、VMess WS、XHTTP 和 Hysteria2；Reality 套餐提供 VLESS Reality 和 XHTTP Reality，并可按需启用 Hysteria2。
- **配置可读、可维护**：Xray、Nginx、systemd 和分享链接采用模板与 profile 管理，脚本负责渲染和检查，重要配置不会散落在难以维护的 Bash 字符串里。
- **证书流程更稳**：证书管理会先展示证书库存、解析结果、端口占用和网络栈状态，再推荐 HTTP-01 或 DNS-01，减少因为 DNS、防火墙或端口冲突导致的反复失败。
- **面向真实网络环境**：安装和路由逻辑会考虑 IPv4-only、IPv6-only、双栈、多公网 IP、WARP 默认路由和 WARP 专用接口等常见 VPS 场景。
- **内置 Hysteria2，不额外拉服务**：使用 Xray-core 内置 Hysteria2，占用 UDP/443，与 TCP/443 上的 Nginx/Xray 分流共存，账号跟随现有用户体系。
- **失败前先检查**：涉及 Nginx、Xray、证书、端口、防火墙的关键操作会尽量先做状态检查或配置测试，避免无提示写坏运行环境。

## 功能特性

- 只使用 Xray-core，不引入 sing-box、订阅系统或外部 Hysteria YAML 服务。
- TLS 套餐默认包含 `VLESS-TCP`、`VLESS-WS`、`VMess-WS`、`XHTTP` 和 Xray-core 内置 `Hysteria2`。
- Reality 套餐包含 `VLESS-TCP Reality Vision` 和 `XHTTP Reality`，安装时可选择同时启用 Hysteria2。
- 支持多用户管理、分享链接生成、自定义 UUID、端口管理、日志查看、卸载与脚本更新。
- 支持 ACME 证书申请与续签，包含 HTTP-01、DNS-01、Cloudflare、DNSPod、Aliyun 和手动 TXT。
- 支持 IPv4-only、IPv6-only、双栈、多公网 IP、WARP 专用接口与 WARP 默认路由场景。
- 支持黑名单、CN IP/域名策略、WARP 分流、IPv4/IPv6 出站策略。
- 支持 Nginx 伪装站管理，配置写入前会执行配置测试，失败时不继续重启。
- 按当前 Xray-core 正式能力启用 VLESS Encryption、REALITY ML-DSA-65、TLS ECH、Hysteria2 `finalmask.quicParams` 等增强字段；内核不支持时会提示升级，不生成不可运行配置。

## 支持协议

| 套餐 | 协议 | 说明 |
| --- | --- | --- |
| TLS | VLESS TCP Vision | TCP/443 入口，负责 TLS 分流与回落 |
| TLS | VLESS WS TLS | 兼容 WebSocket 客户端和 CDN 场景 |
| TLS | VMess WS TLS | 保留 legacy 客户端兼容 |
| TLS | VLESS XHTTP TLS | 默认经 Nginx 反代到本机 Xray |
| TLS | Hysteria2 | Xray-core 内置协议，占用 UDP/443 |
| Reality | VLESS TCP Reality Vision | 默认推荐的 Reality 入口 |
| Reality | VLESS XHTTP Reality | Reality 环境下的 XHTTP 入口 |
| Reality 可选 | Hysteria2 | 复用或申请同域名 TLS 证书 |

更多协议和分享链接说明见 [协议说明](docs/protocols.md)。

## 系统要求

- 建议使用纯净系统：Debian 11/12 或 Ubuntu 20.04/22.04/24.04。
- 需要 root 用户执行。
- 需要一个已解析到服务器的域名；Reality 目标域名不是证书域名。
- 服务器安全组/云防火墙需要放行 TCP/80、TCP/443；启用 Hysteria2 时还需要放行 UDP/443。
- CentOS 可尝试使用，但不作为首选环境；过旧系统不建议使用。

## 安装

```bash
wget -P /root -N --no-check-certificate "https://raw.githubusercontent.com/Suysker/xray-agent/master/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

首次只下载单个 `install.sh` 时，脚本会自动铺设完整运行目录。安装完成后可以通过以下命令重新打开菜单：

```bash
vasma
```

运行时入口：

```text
/etc/xray-agent/install.sh
```

快速开始见 [快速开始](docs/getting-started.md)。

## 菜单概览

```text
1. 安装TLS套餐
2. 安装Reality套餐
3. 账号管理
4. 更换伪装站
5. 证书管理
6. IPv4/IPv6出站策略
7. 阻止访问黑名单及中国大陆IP
8. WARP分流及中国大陆域名+IP
9. 添加新端口
10. 流量嗅探管理
11. sockopt进阶管理
12. Hysteria2管理
13. 订阅管理
14. core管理
15. 更新脚本
16. 查看日志
17. 卸载脚本
18-24. AdGuardHome、WARP、BBR、测速、回程、流媒体、VPS信息
```

完整说明见 [菜单参考](docs/menu-reference.md)。

## 文档

- [快速开始](docs/getting-started.md)
- [协议说明](docs/protocols.md)
- [证书管理](docs/certificates.md)
- [网络与路由](docs/network-routing.md)
- [菜单参考](docs/menu-reference.md)
- [配置与目录](docs/configuration.md)
- [故障排查](docs/troubleshooting.md)
- [安全与兼容性](docs/security-and-compatibility.md)

## 注意事项

- 如果域名接入 Cloudflare，使用 TLS/WS/XHTTP/CDN 场景时请确认 SSL/TLS 模式为 Full 或 Full(strict)。
- Oracle Cloud、GCP、部分云厂商有额外安全组或本机防火墙，请同时检查云控制台和系统防火墙。
- Hysteria2 使用 UDP/443，不会占用 TCP/443；但云防火墙必须单独放行 UDP。
- Reality 的目标域名应选择真实、稳定、证书链合理的站点；不要把 Reality 目标域名当作自己的证书域名。
- 修改证书、Nginx、端口和路由前，建议先确认当前菜单中的状态提示。

## License

本项目基于 [AGPL-3.0](LICENSE) 许可证发布。
