# certificates

- `lib/tls.sh` 负责 ACME 服务商选择、邮箱注册、证书申请、更新、删除、Reality 目标域名和证书菜单。
- `lib/system.sh` 负责 `RenewTLS` 定时任务。
- 证书文件统一存放在 `/etc/xray-agent/tls`。
- Hysteria2 复用同目录下的 TLS 证书；Reality-only 环境启用 Hysteria2 时也通过现有证书流程复用或申请证书。Hysteria2 的 SNI/证书域名必须是用户控制的真实域名，默认回车使用当前 Xray TLS 域名，不使用 Reality 目标域名签证书。

- ACME 申请、证书安装、续签、删除在 `lib/tls.sh`
- Reality 目标域名与 serverNames 在 `lib/tls.sh`
