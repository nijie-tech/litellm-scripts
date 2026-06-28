# 使命聚焦:从"学搭网关"转为"C 端 agent gateway 的配置最佳实践"

第 05 课后,用户说明了真实诉求:已自研一款**面向 C 端用户的 agent**,计划用 **LiteLLM 作 AI gateway**,最想要的是**配置的最佳实践**。前 5 课的机制("大体已经明白")是手段,不是目的。

据此更新了 [[MISSION.md]]:
- 计费模式 = **产品方统一付费** → end-user(`user` 字段)粒度的花费跟踪 + 限额/限速防滥用成为重点。
- 规模 = **单实例起步**,架构预留多实例(Redis 共享状态只作扩展路径提及)。
- 四个最佳实践维度全要:成本/防滥用、延迟流式、可靠容灾、内容安全护栏。

含义(影响后续 ZPD):
- 教学换档——从"怎么配"转为"对 C 端 agent 该怎么配、为什么"。产出以**可长期回看的最佳实践参考卡**为核心。
- 新引入概念:end-user 预算(`max_end_user_budget` / `/budget/new` + `/customer/new`)、guardrails(presidio PII / moderation)、生产基线(`LITELLM_MODE`、`salt_key`、`json_logs`)。
- 已掌握机制(虚拟 key、fallback、缓存、callbacks)不再重讲,只在最佳实践里点到取舍。

待修正:第 05 课(缓存)教了 `REDIS_URL`;官方生产文档建议**用 redis host/port/password 而非 redis_url**(后者约慢 80 RPS)。已在最佳实践参考卡里纠正。
