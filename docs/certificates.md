# certificates

- `lib/tls.sh` 负责 ACME 服务商选择、邮箱注册、证书申请、更新、删除、Reality 目标域名和证书菜单。
- `lib/system.sh` 负责 `RenewTLS` 定时任务。
- 证书文件统一存放在 `/etc/xray-agent/tls`。

- ACME 申请、证书安装、续签、删除在 `lib/tls.sh`
- Reality 目标域名与 serverNames 在 `lib/tls.sh`
