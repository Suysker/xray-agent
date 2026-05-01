# 快速开始

## 安装前准备

- 使用 root 用户登录服务器。
- 推荐系统：Debian 11/12、Ubuntu 20.04/22.04/24.04。
- 准备一个已经解析到服务器的域名。
- 确认云厂商安全组放行 TCP/80、TCP/443；启用 Hysteria2 时还需要放行 UDP/443。
- 建议使用纯净系统，避免已有 Nginx、证书脚本或代理脚本占用端口和配置。

## 一键安装

```bash
wget -P /root -N --no-check-certificate "https://raw.githubusercontent.com/Suysker/xray-agent/master/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

安装脚本会自动铺设完整运行目录，并在安装完成后创建快捷命令：

```bash
vasma
```

运行时入口为：

```text
/etc/xray-agent/install.sh
```

## 首次推荐流程

1. 运行安装命令进入菜单。
2. 选择 `1.安装TLS套餐` 或 `2.安装Reality套餐`。
3. 按提示输入域名、端口、证书申请方式和账号信息。
4. 安装完成后查看脚本输出的分享链接。
5. 使用客户端导入分享链接并连接测试。

TLS 套餐适合希望使用同域名证书、Nginx 伪装站、XHTTP、Hysteria2 的场景。Reality 套餐适合使用 Reality 目标站点伪装的场景，安装时可选择是否同时启用 Hysteria2。

## 更新、卸载和重新打开菜单

- 重新打开菜单：`vasma`
- 更新 Xray-core：菜单 `14.core管理`
- 更新脚本：菜单 `15.更新脚本`
- 创建/恢复备份：菜单 `16.备份与恢复管理`
- 卸载脚本：菜单 `18.卸载脚本`

升级、重装或卸载前建议先使用菜单 `16.备份与恢复管理` 创建备份。卸载前请确认是否需要保留 `/etc/xray-agent/tls` 下的证书文件。

## 常见注意事项

- Cloudflare CDN 场景请确认 SSL/TLS 模式为 Full 或 Full(strict)。
- Oracle Cloud 需要同时检查系统防火墙和云控制台安全列表。
- Hysteria2 使用 UDP/443，TCP/443 仍由 Nginx/Xray 分流使用。
- IPv6-only 或 WARP 默认路由环境中，脚本会按当前网络能力调整可用动作，但域名解析和云防火墙仍需要手动确认。
