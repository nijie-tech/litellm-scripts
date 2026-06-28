# Mission: 用 LiteLLM 给 C 端 Agent 搭 AI Gateway —— 配置最佳实践

> 2026-06-25 聚焦:用户已自研一款面向 C 端用户的 agent,计划用 LiteLLM 作为 AI gateway。
> 机制已基本掌握(见 learning-records 0001–0003),核心诉求转为**配置的最佳实践**。
> 原"按步骤学搭网关"的旧使命见 [[0004-mission-shift-to-best-practices]]。

## Why
为自研的 **C 端 agent 产品**搭一个 **LiteLLM AI gateway**,并以**生产最佳实践**配置它:
统一接入 OpenAI + 国内模型,在"产品方统一付费"的前提下做到**成本可控防滥用、低延迟流式体验、故障不掉线、内容合规**——让网关稳、省、快、安全地撑住面向消费者的流量。

## Success looks like
- 手里有一份**带注释的生产级 config.yaml 最佳实践模板**,能讲清每个配置块"为什么这么设"
- 成本/防滥用:按 **end-user(`user` 字段)** 跟踪花费,设每用户预算/限速 + 全局成本护栏 + 超额告警
- 延迟/流式:流式透传、合理 `request_timeout` / `num_retries`(C 端要"快失败")、缓存命中省钱降延迟
- 可靠性:OpenAI 与国内模型**互为 fallback**、`context_window_fallbacks`、`allow_requests_on_db_unavailable`
- 内容安全:`guardrails`(PII 脱敏 / moderation)在 pre/post call 拦截
- 通用生产基线:`LITELLM_MODE=PRODUCTION`、`master_key`+`salt_key`、`json_logs`、非 root 镜像等

## Constraints
- 用户熟悉 Python、调过大模型 API,前 5 课已掌握 Proxy 机制(config 四抽屉、虚拟 key、fallback、监控、缓存)
- 全程中文教学;偏好"直接给最佳实践 + 为什么",不需要再啰嗦基础机制
- 计费模式:**产品方统一付费**(故 end-user 粒度限额/防滥用是重点)
- 规模:**单实例起步**,但架构预留多实例扩展能力
- 接入:OpenAI(GPT)+ 国内模型(OpenAI 兼容 / 自定义 endpoint)

## Out of scope(暂不追)
- LiteLLM Python SDK 在业务代码里的深度用法(聚焦 Proxy gateway)
- 自训/自部署底层模型(只关心如何接入)
- 企业版 SSO / 高级 RBAC
- 多实例 K8s 大规模运维(单实例起步;Redis 共享状态只作"扩展路径"提一句)
