# 已掌握:启动 Proxy + config.yaml 心智模型

用户完成第 01 课的可见成果:在本机用 `pip install 'litellm[proxy]'` + `litellm --config config.yaml` 跑通了网关,并通过 OpenAI 兼容接口调通了 OpenAI 与一个国内模型。

确立的起点(影响后续 ZPD):
- 理解 config.yaml 四抽屉(model_list / litellm_settings / general_settings / router_settings)。
- 理解 `model_name`(对外名)vs `litellm_params.model`(真实串)的间接关系。
- 掌握国内模型"`openai/<模型>` + `api_base`"兼容通法,以及 `os.environ/KEY` 取密钥。

含义:可以直接进入 `general_settings` 抽屉(master_key + 虚拟 key + 预算/限流),无需再回顾 model_list 基础。下一个新概念是**需要 Postgres 数据库**才能生成虚拟 key。
