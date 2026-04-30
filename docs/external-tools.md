# external-tools

- 菜单 `18` -> `lib/external.sh` -> `xray_agent_external_warp_menu`
- 菜单 `19` -> `lib/external.sh` -> `xray_agent_external_kernel_bbr`
- 菜单 `20` -> `lib/external.sh` -> `xray_agent_external_hyperspeed`
- 菜单 `21` -> `lib/external.sh` -> `xray_agent_external_backtrace`
- 菜单 `22` -> `lib/external.sh` -> `xray_agent_external_unlock_media`
- 菜单 `23` -> `lib/external.sh` -> `xray_agent_external_vps_info`

Hysteria2 已从外部 Hysteria 一键脚本改为 Xray-core 内置协议管理，并显示在工具管理分组；因此它不再属于外部工具列表。其余菜单只做外部脚本调用，入口已从 `install.sh` 内嵌实现迁移到独立模块。

- 18 -> warp 菜单
- 19 -> 内核与 BBR
- 20 -> hyperspeed
- 21 -> backtrace
- 22 -> 流媒体解锁
- 23 -> VPS 信息
