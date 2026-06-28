# LiteLLM Proxy 网关 Resources

## Knowledge

- [LiteLLM Proxy Quick Start(官方)](https://docs.litellm.ai/docs/proxy/quick_start)
  最权威的上手文档。Use for: 安装、最小启动、第一次调用。

- [Proxy Config — config.yaml 完整字段参考(官方)](https://docs.litellm.ai/docs/proxy/config_settings)
  config.yaml 四大顶层段(model_list / litellm_settings / general_settings / router_settings)的逐字段说明。Use for: 查任何一个配置项到底放哪、什么含义。

- [Proxy Configs 教程(官方)](https://docs.litellm.ai/docs/proxy/configs)
  config.yaml 的结构与示例:model_name vs litellm_params、os.environ/KEY、自定义 api_base。Use for: 写 model_list、接 OpenAI 兼容的国内模型。

- [Virtual Keys / 预算 / 限流(官方)](https://docs.litellm.ai/docs/proxy/virtual_keys)
  master_key 与虚拟 key 的发放、预算与速率限制。Use for: 多应用/团队凭证管理(后续课程)。

- [Reliability — Fallbacks / 负载均衡 / 重试(官方)](https://docs.litellm.ai/docs/proxy/reliability)
  router_settings 的路由策略、fallback、retry。Use for: 生产可靠性(后续课程)。

- [Logging / Callbacks(官方)](https://docs.litellm.ai/docs/proxy/logging)
  把请求花费、延迟打到 Langfuse / Prometheus / 文件等。Use for: 可观测性(后续课程)。

- [Docker 部署(官方)](https://docs.litellm.ai/docs/proxy/deploy)
  生产部署、挂 Postgres。Use for: 上线(后续课程)。

## Wisdom(Communities)

- [LiteLLM GitHub Discussions / Issues](https://github.com/BerriAI/litellm)
  作者活跃,真实坑大多能在 issue 里搜到。Use for: 报错排查、确认某厂商支持情况。
- [LiteLLM Discord](https://discord.com/invite/wuPM9dRgDw)
  官方社区,问配置/路由实战问题。Use for: 配置评审、生产实践提问。

## Gaps
- 国内模型(通义/DeepSeek/智谱/文心等)接入 LiteLLM 的**中文实战指南**质量参差;暂以"OpenAI 兼容 + 自定义 api_base"通法为准,逐个厂商验证后再补充到这里。
