# migration-plan

- 升级顺序固定为：铺设新目录 -> 迁移模板到 `templates/xray/{base,inbounds,outbounds,extras}` -> 删除旧 `profiles/*.env` -> 删除旧平铺 `lib/*.sh`。
- `packaging/upgrade.sh` 是仓库布局迁移入口，负责旧模板名与旧 profile 名收口。
- `lib/runtime/migrate.sh` 是运行时钩子，只做幂等型目录和配置文件名修正。
- 回滚方式：重新部署上一个版本的完整 `/etc/xray-agent` 布局，而不是只回滚单个脚本文件。
- 升级后验证必须执行 `verify/smoke.sh`、`verify/render-protocols.sh`、`verify/routing-check.sh`、`verify/share-link-check.sh`。
