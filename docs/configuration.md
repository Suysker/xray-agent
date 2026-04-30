# 配置与目录

默认运行目录为：

```text
/etc/xray-agent
```

## 主要目录

| 路径 | 说明 |
| --- | --- |
| `/etc/xray-agent/install.sh` | 管理入口 |
| `/etc/xray-agent/lib` | 脚本运行模块 |
| `/etc/xray-agent/profiles` | 安装组合、协议、路由描述 |
| `/etc/xray-agent/templates` | Xray、Nginx、systemd、分享链接模板 |
| `/etc/xray-agent/tls` | TLS 证书和 acme 日志 |
| `/etc/xray-agent/xray` | Xray-core、geosite、geoip |
| `/etc/xray-agent/xray/conf` | Xray 拆分 JSON 配置 |
| `/etc/nginx/conf.d` | Nginx 站点配置 |

## 模板原则

模板只放完整配置文件、重要配置块和稳定外部格式，例如：

- Xray inbound、outbound、基础配置。
- Nginx 站点配置。
- systemd unit。
- 分享链接格式。

一行默认值、小数组、cron 行、包源行、临时 routing rule 不单独做模板，避免配置被拆得过碎。

## 备份建议

升级或迁移前建议备份：

```bash
tar -czf /root/xray-agent-backup.tgz /etc/xray-agent /etc/nginx/conf.d
```

如果只想保留证书，至少备份：

```text
/etc/xray-agent/tls
```

## 手动修改提醒

不建议直接编辑 `/etc/xray-agent/xray/conf` 下的配置文件。菜单重新渲染配置时，手工改动可能被覆盖。需要长期保留的改动应优先通过菜单、profile 或模板完成。
