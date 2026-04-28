# migration-plan

- 升级顺序固定为：铺设新目录 -> 迁移模板到 `templates/` 下的运行时配置目录 -> 删除旧 `profiles/*.env` -> 删除旧碎片化 `lib/<domain>/*.sh` 目录 -> 删除旧运行时 `verify/` 和 `scripts/`。
- `packaging/upgrade.sh` 是仓库布局迁移入口，负责旧模板名与旧 profile 名收口。
- `lib/runtime.sh` 是运行时钩子，只做幂等型目录和配置文件名修正。
- `install.sh` 支持从单文件入口 bootstrap 完整仓库布局；菜单 13 更新脚本时也必须铺设完整布局，而不是只替换入口脚本。
- 回滚方式：重新部署上一个版本的完整 `/etc/xray-agent` 布局，而不是只回滚单个脚本文件。
- 升级后验证使用 README 的手工命令；仓库不保留一键验证脚本。
