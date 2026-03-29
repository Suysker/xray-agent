name=warp
domain_strategy=AsIs
dns_query_strategy=UseIP
outbound_order=IPv4-out,IPv6-out,blackhole-out,warp-out
rule_mode=warp
outbound=warp-out
