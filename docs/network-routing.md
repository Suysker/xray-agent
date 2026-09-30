# 网络与路由

> 本页说明当前实现。单栈通过 WARP 补全双栈时的对称规则及验收边界，见[架构方案第 1.2–1.3 节](network-egress-design.md#12-单栈补全的对称出口规则)。

核心目标是：一键开启/关闭中国大陆网站或目标 IP 的 WARP 分流，通过外部 WARP 补全单栈，以及让用户选择默认出口并维护自己的 WARP 名单。中国大陆分流不是强制默认项；这些目标的完整实现状态以架构方案为准。

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
| Xray 默认出口 | 菜单 `6` | 同时设置 TCP/UDP 默认出口和地址族优先级；高级入口可单独覆盖 UDP 出口 |
| Xray 规则分流 | 菜单 `7`、`8` | 按域名、geosite、IP 或 geoip 使用明确出口 |

系统全局 WARP、Xray 默认出口和 Xray 规则分流互不混用。菜单 `20` 返回后脚本会刷新实时网络状态；如果原策略中的出口变得不可用，只提示用户调整，不自动回退。

系统已配置单栈补全时，默认 TCP/UDP 沿系统路径：原生 IPv6 场景初始 IPv6 优先，原生 IPv4 场景初始 IPv4 优先；缺失地址族使用已验证的 WARP 路径。Xray 名单不影响普通本机程序，Xray 优先级也不保证整机应用的地址排序。

### WARP 名单与中国大陆开关

菜单 `8` 的常用入口：

- `1` 编辑完整 WARP 域名名单，如 `example.com,geosite:netflix`。裸域名匹配主域和子域；裸列表名如 `netflix` 视作 geosite。不要输入 URL。
- `2` 独立开启/关闭中国大陆网站 **或** 目标 IP 走 WARP。生成器拆分域名/IP 规则，任一命中即可；关闭不清空自定义名单。
- 名单清空后提交仅移除 `warp-domains`；中国大陆开关使用 `cn-egress`，不要求逐站创建规则。
- 新建或重设名单时沿用当前默认地址族优先级；后续改变默认策略不会隐式重写已有规则。高级规则入口保留独立选择能力。

WARP 不可用时拒绝启用，不静默改走原生。若已有中国大陆 IP 黑名单，须先关闭该阻断再开启中国大陆 WARP 分流。私网阻断始终先于名单匹配。

## 策略唯一来源

用户策略保存在：

```text
/etc/xray-agent/state/egress-policy.json
```

示例：

```json
{
  "schemaVersion": 2,
  "defaultTcpEgress": "system-auto-out",
  "defaultPreference": "ipv6",
  "defaultUdpEgress": "system-auto-out",
  "rules": [
    {
      "id": "openai-via-warp",
      "match": {
        "domain": ["geosite:openai"]
      },
      "tcpEgress": "warp-auto-out",
      "preference": "ipv6",
      "udpEgress": "warp-auto-out"
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

UDP 不使用 Happy Eyeballs。自动出口使用 Freedom `ForceIPv6v4` / `ForceIPv4v6`，优先解析指定地址族，没有该族记录时才使用另一族。IP 字面量保持目标地址族，WARP 名单始终绑定 WARP。**这不是 UDP 不可达后的自动重试或竞速。**

需要强制单族时仍可选择物理出口：

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

当前 schema 为 2，共享 `defaultPreference` / `preference` 替代旧的 `defaultTcpPreference` / `tcpPreference`；schema 1 不会被自动转换。不要只替换脚本后继续使用旧策略或手工维护派生 JSON。

## 验证

仓库测试：

```bash
bash tests/egress_catalog_test.sh
bash tests/network_policy_test.sh
bash tests/egress_policy_test.sh
XRAY_AGENT_TEST_XRAY_BINARY=/path/to/xray bash tests/xray_freedom_integration_test.sh
XRAY_AGENT_TEST_XRAY_BINARY=/path/to/xray \
XRAY_AGENT_TEST_ARTIFACT_DIR=/tmp/egress-verification \
  bash tests/egress_integration_test.sh
```

双栈集成测试需要 Linux 网络命名空间权限及 Python 3；它创建隔离网络，不修改主机公网路由。指定的产物目录保留生成配置、Xray 日志和结果 JSON，可用于复核两种优先级下 TCP/UDP、单族域名、字面量、名单或匹配及私网阻断。

本地模拟和多版本 Xray 集成测试不能代替真实 VPS 出口核对。两类单栈补全场景已有局部在线验证，但尚不能视为完整验收；必须按架构方案核对原生地址族优先、名单任一条件命中、UDP/IP 字面量与菜单管理一致性，并补齐原生双栈场景及系统 WARP 模式切换。验证记录应区分期望出口、实际公网出口和是否经过真实客户端入口，不披露具体部署身份或凭据。

## 本机转发地址

脚本会根据系统能力选择本机服务之间的转发地址：IPv4 可用时优先使用 `127.0.0.1`，IPv6-only 或无 IPv4 回环时使用 `::1`。这部分与公网出口策略独立。
