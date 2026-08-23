# 网络与路由

xray-agent 将“出口提供者”和“地址族”分开建模。WARP 的安装、更新、注册、Endpoint 和基础 WireGuard 模式继续由当前外部脚本提供；xray-agent 自己维护调用适配、实时网络识别、项目自有策略路由、出口目录和 Xray 分流。

实施前问题和十五种系统组合见 [IPv4/IPv6 与 WARP 出站现状基线](network-egress-current-state.md)，架构依据见 [IPv4/IPv6 与 WARP 四出口架构方案](network-egress-design.md)。

## 出口目录

运行时根据真实接口、源地址、绑定接口公网结果、原生/WARP 身份和 Xray 版本生成七类候选：

| 出口 ID | 含义 |
| --- | --- |
| `native-ipv4-out` | 明确使用原生 IPv4 |
| `native-ipv6-out` | 明确使用原生 IPv6 |
| `warp-ipv4-out` | 明确使用 WARP IPv4 |
| `warp-ipv6-out` | 明确使用 WARP IPv6 |
| `system-auto-out` | 使用 Linux 当前 IPv4/IPv6 路径进行 TCP 双栈竞速 |
| `native-auto-out` | 在同一个原生双栈接口内进行 TCP 双栈竞速 |
| `warp-auto-out` | 在同一个 WARP 双栈接口内进行 TCP 双栈竞速 |

接口只有地址或只有内核路由不代表公网可用。物理出口必须绑定目标接口完成真实公网请求，并核对返回地址族和 Cloudflare `warp` 身份；对应出口失败时标记为不可用，不能保存到策略，也不会静默改走其他提供者。`ip route get` 保留为诊断信息，但不能单独否决已经成功的 `SO_BINDTODEVICE` 实测。

## 三层控制面

| 控制层 | 管理入口 | 含义 |
| --- | --- | --- |
| Linux 系统 WARP | 菜单 `20` | 调用外部 WARP 脚本改变系统级模式 |
| Xray 默认出口 | 菜单 `6` | 分别选择 TCP 默认出口、TCP 地址族优先级和 UDP 默认出口 |
| Xray 规则分流 | 菜单 `7`、`8` | 按域名、geosite、IP 或 geoip 使用明确出口 |

系统全局 WARP、Xray 默认出口和 Xray 规则分流互不混用。菜单 `20` 返回后脚本会刷新实时网络状态；如果原策略中的出口变得不可用，只提示用户调整，不自动回退。

## 策略唯一来源

用户策略保存在：

```text
/etc/xray-agent/state/egress-policy.json
```

示例：

```json
{
  "schemaVersion": 1,
  "defaultTcpEgress": "system-auto-out",
  "defaultTcpPreference": "ipv6",
  "defaultUdpEgress": "native-ipv4-out",
  "rules": [
    {
      "id": "openai-via-warp",
      "match": {
        "domain": ["geosite:openai"]
      },
      "tcpEgress": "warp-auto-out",
      "tcpPreference": "ipv4",
      "udpEgress": "warp-ipv4-out"
    }
  ]
}
```

以下文件是派生产物，不应手工维护：

```text
/etc/xray-agent/xray/conf/09_routing.json
/etc/xray-agent/xray/conf/10_outbounds.json
/etc/xray-agent/xray/conf/11_dns.json
```

脚本启动时会检测策略和派生配置是否漂移。策略有效且出口仍可用时会重新生成派生配置；校验失败则保留旧配置。

## TCP 优先与回退

自动出口要求 Xray-core `v25.6.8+`。实现链路为：

```text
routing.domainStrategy=IPOnDemand
-> 私网和保留地址进入 blackhole-out
-> Freedom.settings.domainStrategy=AsIs
-> Xray-core v26.5.3+ 添加首条无条件 finalRules allow
-> sockopt.domainStrategy=UseIP
-> sockopt.happyEyeballs
```

用户可以分别选择 IPv4 优先或 IPv6 优先。首选地址族立即拨号，另一地址族在 250ms 后加入竞速。

真实 VLESS 入站测试已经覆盖 Xray-core `v25.6.8`、`v26.5.9` 和 `v26.7.28`：

- IPv4 优先和 IPv6 回退。
- IPv6 优先和 IPv4 回退。
- 新版 Freedom `finalRules` 放行后，路由层仍阻断私网目标。

Happy Eyeballs 只解决同一个自动出口内、TCP 双栈域名的地址竞速，不是任意两个 outbound 之间的健康检查。

## UDP

UDP 不使用 Happy Eyeballs。菜单只允许选择明确的单地址族物理出口：

```text
native-ipv4-out
native-ipv6-out
warp-ipv4-out
warp-ipv6-out
```

目标不支持所选地址族时连接明确失败，不自动更换提供者或地址族。

## 项目网络策略

WARP 全局模式下，如果策略明确选择原生出口，xray-agent 会为绑定的原生源地址维护优先于 WARP 的 `lookup main` 规则。资源记录在：

```text
/etc/xray-agent/state/network-ownership.json
```

项目规则使用独立优先级、幂等应用，并只清理由该所有权文件记录的资源。遇到同优先级外部规则时拒绝应用，不收养、不覆盖，也不删除外部资源。

## 安装范围

本出口架构只保证全新安装。新安装直接创建 `egress-policy.json` 和对应派生配置，不读取、不识别也不迁移历史 `IPv4-out`、`IPv6-out` 或旧 WARP 路由配置。

旧安装升级到该架构不在本次实现范围内；需要使用新架构时应先独立备份，再按全新安装流程部署和重新配置出口策略。

## 验证

仓库测试：

```bash
bash tests/egress_catalog_test.sh
bash tests/network_policy_test.sh
bash tests/egress_policy_test.sh
XRAY_AGENT_TEST_XRAY_BINARY=/path/to/xray bash tests/xray_freedom_integration_test.sh
```

本地模拟和多版本 Xray 集成测试不能代替真实 VPS 出口核对。“原生 IPv4 + WARP IPv6”和“原生 IPv6 + WARP IPv4”已完成在线验收；发布完成定义仍要求在“原生双栈 + WARP 双栈”节点记录期望出口和实际公网出口，并补齐系统 WARP 模式切换与完整 UDP/IP 字面量矩阵。

## 本机转发地址

脚本会根据系统能力选择本机服务之间的转发地址：IPv4 可用时优先使用 `127.0.0.1`，IPv6-only 或无 IPv4 回环时使用 `::1`。这部分与公网出口策略独立。
