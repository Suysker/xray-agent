# 安全与兼容性

本项目的配置策略以 Xray-core 正式版可解析、主流客户端可导入、运行时不生成明显错误配置为目标。它不能保证在任何网络环境中永久可用，也不承诺绝对不可识别。

## Xray-core 正式版能力

脚本会检测当前 Xray-core 是否支持相关命令和字段。支持时启用，不支持时提示升级，不生成当前内核无法运行的配置。

- VLESS Encryption：用于无回落的 VLESS WS/XHTTP。
- REALITY ML-DSA-65：目标站点预检合适时启用，分享链接输出 `pqv`。
- TLS ECH：支持时生成服务端 ECH 配置，分享链接输出 `ech`。
- Hysteria2 QUIC 参数：使用 `finalmask.quicParams`，不写旧字段。

部分能力需要 Xray-core v26.3.27 或更新版本。建议通过菜单 `13.core管理` 使用正式版。

## 为什么不是所有入口都启用 VLESS Encryption

Xray-core 要求 VLESS `decryption` 非 `none` 时不能与 `fallbacks` 共用。TLS TCP 和 Reality TCP 入口承担分流和回落，因此保持 `encryption=none`。VLESS WS 和 XHTTP 没有这类回落要求，默认可使用 VLESS Encryption。

## REALITY 目标站点

Reality 目标站点应选择真实、稳定、证书链合理的站点。脚本会在生成 ML-DSA-65 前做目标 TLS 预检；不合适时跳过 `pqv` 并提示更换目标站点，避免为了追新字段生成异常行为。

## TLS ECH

ECH 可以减少部分 TLS 明文指纹暴露，但它不是万能保护。客户端需要支持分享链接中的 `ech` 字段；如果客户端不支持，可继续使用不带 ECH 的 TLS 分享链接。

## Hysteria2

Hysteria2 使用 UDP/443，与 TCP/443 不冲突。它适合 UDP 质量较好的线路，但对云防火墙、运营商 UDP 策略和多公网出口路由更敏感。带宽参数只写在服务端，不写进分享链接。

## VMess 兼容性

VMess WS TLS 保留是为了兼容旧客户端。新部署优先使用 VLESS、Reality、XHTTP 或 Hysteria2。

## 使用建议

- 使用真实域名和有效证书。
- 避免在同一台服务器上混用多个脚本管理同一套 Nginx/Xray 配置。
- 定期更新 Xray-core 正式版。
- 复杂网络环境中先确认 IPv4/IPv6、WARP、云防火墙和本机防火墙状态。
