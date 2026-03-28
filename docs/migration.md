# migration

本轮重构把仓库从单文件安装脚本推进到模块化骨架：

- `install.sh` 继续保留入口、交互和兼容流程
- `lib/` 承载配置渲染、feature patch、用户导出与本地模式逻辑
- `templates/` 承载 Xray 和 Nginx 的结构模板
- `profiles/` 承载核心 profile 与扩展 profile 的定义

迁移原则：

- 旧菜单保持兼容
- 核心四个 profile 改由统一渲染器生成
- XHTTP、REALITY、Hysteria2、TUN 通过模块化函数扩展
- 实验能力默认关闭，通过 `feature-flags.env` 开关启用
