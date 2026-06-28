# 已掌握:负载均衡 + retry vs fallback

用户完成第 03 课:配置同名多部署做负载均衡,并通过"故意改坏 gpt-4o 的 key"验证了 fallback 自动切到备用模型。

确立的起点:
- "一个 model_name = 一个逻辑模型,背后挂 N 个物理部署"的负载均衡模型已内化。
- 已分清 retry(同逻辑模型再试,litellm_settings.num_retries)与 fallback(切到另一模型名,litellm_settings.fallbacks)。
- 知道 fallbacks/num_retries 属于 litellm_settings 抽屉,routing_strategy 属于 router_settings。

含义:可靠性主线打通。可进入可观测性(litellm_settings.callbacks)。后续讲多实例部署时,再引入 router_settings 的 Redis 共享路由状态即可。
