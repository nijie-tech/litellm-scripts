# 教学笔记 / 偏好

## 用户画像
- 熟悉 Python,调过大模型 API(OpenAI/Claude 级别);没搭过代理网关。
- 全局规范:**始终用中文回复**。

## 教学偏好
- 中文教学。
- 重实战:每课要有一个能立刻跑起来的"可见成果"。
- 关注生产:可靠性、可观测性、key 管理是后续主线。

## 课程主线规划(草案,按 ZPD 推进)
1. ✅ 0001 — 启动第一个 Proxy:最小 config.yaml,接 OpenAI + 国内模型,跑通调用。
2. ✅ 0002 — master_key + 虚拟 key:多应用凭证、预算、限流(需 Postgres)。
3. ✅ 0003 — router_settings:同名模型多部署 + 负载均衡 + fallback。
4. ✅ 0004 — 可观测性:callbacks 打花费/延迟到 Prometheus/Langfuse。
5. ⏭️ Docker + Postgres 生产部署 —— 用户主动跳过,延后(随时可回来)。
6. ✅ 0005 — 缓存:cache + Redis,省钱降延迟;exact vs 语义缓存。
6.5 ✅ 使命聚焦 → C 端 agent gateway 最佳实践(见 LR 0004,MISSION 已更新)。
7. ✅ 0006 — C 端 gateway 配置决策框架(集大成)+ reference/best-practices-c-end-gateway.html(核心成果)。
8. ⬜ (候选)针对用户真实请求流的"逐行定制版 config.yaml"。
9. ⬜ (候选)免费/付费分层套餐落地;国内 guardrail/moderation 接入。
10. ⬜ (候选,延后)多实例水平扩展:Redis 共享状态;Docker+Postgres 部署。

## 路由决策(2026-06-25 定案)
- 试过 LiteLLM 内置 Complexity Router(smart-router):中文全部掉 SIMPLE。【源码定论根因】complexity_router.py 关键词匹配单词走 `\b`+re 词边界,连续无空格中文匹配不上(只有含空格英文短语走子串);且 token 数按 len//4 估,中文低估 4~8 倍。两处写死、非可配。所有 4 个 keyword 列表(含 technical_keywords/simple_keywords)虽可配,但 `\b` 匹配让中文配了也无效。A 对中文代码级不兼容,正式判死。
- 已删 smart-router(DB 删除成功,/model/info 干净 8 模型;运行进程可能需 reload 才完全失效,无碍——B 不调它)。
- 最终方案 = B 应用层路由:scripts/app_side_router_example.py(功能入口 FEATURE_MODEL + 中文复杂度打分 + 会话内不降档 + explain 观测)。已验证中文正确分档。网关只管接入/计费/限额/兜底/监控。

## 网关层语义路由(2026-06-28 实证可行 ✅,与上面判死的 complexity_router 不是一回事)
- 背景:用户要"尽量网关层做掉 + 哑调用方打一个名字就自动分流"。结论:用 LiteLLM 原生**语义版 auto_router**(embedding 相似度),非规则版 complexity_router。
- 机制(源码核实 litellm/router_strategy/auto_router/):`model: auto_router/<name>`,底层是 semantic-router 库的 SemanticRouter。route 的 `name` **直接当目标 model_name**,没命中阈值→`auto_router_default_model`。embedding 走 `auto_router_embedding_model`(必须是 model_list 里的 embedding 部署)。可内联 `auto_router_config`(routes:[{name,utterances,score_threshold}])手写,无需 router.json 文件。
- **中文命门**:embedding 必须用多语/中文模型 + utterances 写中文。英文默认 embedding 会重蹈 RouteLLM 覆辙。
- 【坑1·已绕】DashScope text-embedding-v4 **batch 上限=10**;semantic-router 建索引时把所有 utterances 一次性批量 embedding,>10 直接 400。`LiteLLMRouterEncoder.encode_documents` 把整个 list 塞一次 `embedding(input=docs)`,**不分块、无配置开关**(源码定论)。留 v4 又要 >10 条只能改源码,不值。
- 【解法】embedding 换 **SiliconFlow**(batch 8192/32768)。LiteLLM **无原生 siliconflow provider**,但走 `openai/` 兼容通道即可(`model: openai/BAAI/bge-m3` + `api_base: https://api.siliconflow.cn/v1`)——和现网 DashScope v4 同套路(v4 也是 compatible-mode 兼容通道,无专属 provider)。已建 zh-embed 部署(bge-m3,1024 维)。
- 【坑2·已坐实】改已存在的 auto_router 配置,`/model/new` 改了 DB 但**运行进程按 model_name 缓存 routelayer、热改不刷新**。实证:重建同名 "smart-router" 仍吐旧 route 名(moonshot/kimi-k2.6,871a69db 时代),换全新名 smart-router-v1 立刻生效。**生产规则:路由配置变更 ⇒ reload 网关,或用版本化名(smart-router-v2…)切流。别指望热替换。**
- 【坑3】响应 `.model` 只回路由器名,真实落点要看响应头 `x-litellm-model-id`(再 /model/info 映射回名)或 spend 日志。调阈值时必需。
- **实测(smart-router3,32 条中文例句,4 档,全用例句表外的口语句):4/6 全对,含"Go协程一跑就panic"这种零关键词口语正确命中 kimi-code**(complexity_router 的 `\b` 永远做不到)。1 错:"用numpy写矩阵乘法"被"矩阵"拉向 max(调优面:给 code 档加"用X库实现"类例句 / 调 max 阈值)。
- 迁移套件(自包含,env 驱动,拷到国内新网关直接跑):scripts/setup-smart-router.sh(预检+建 embedding+建路由器+冒烟测试,`--check`/`--test` 子命令)+ scripts/smart-router-routes.json(路由规则数据,改例句只动这个)。另:scripts/provision-smart-router.sh(旧版,依赖 lib.sh)+ scripts/auto-router.config.yaml(文件式部署参考)留作对照。
- 现网留存(2026-06-28 清理后):zh-embed(id 82b839c2,SiliconFlow bge-m3)+ smart-router-v2(id 65f1d79d,34 条例句,可用)。SiliconFlow 用的是临时测试 key 字面量,**生产前挪回 os.environ 并轮换**(master key 也在对话里裸露过,建议一并轮换)。
- 【调优是数据驱动,别盲调】34 条例句未调阈值时:numpy 矩阵乘法→code(对),但"设计百万QPS排行榜"→code(该 max)、"Go协程panic"→plus(该 code)。加 code 例句会增大该档"引力"、带偏边界 case。结论:阈值/例句配比敏感,需真实流量 + 落点统计(待做的观测脚本)迭代,手调=打地鼠。
- 与方案 B 的关系:二者不互斥。A(网关语义)适合哑/第三方调用方;B(应用层)能拿 feature/会话信号、可单测,更准。可 A 兜底 + B 主路。

## 图片模型(2026-06-27 已打通 ✅)
- 放弃 doubao(volc 凭证 key 格式被火山拒,401)。改用 qianwenai 的 wan2.7-image。
- 关键认知:qianwenai 图片【不是】OpenAI /images/generations,是 DashScope 原生 multimodal-generation 端点,非标准协议 → 标准 model 条目接不了 → 用 pass-through。
- 【纠错】pass-through 可以用 API 配!端点 POST/GET/DELETE /config/pass_through_endpoint(我之前误判只能 UI)。schema:path/target/headers/include_subpath/cost_per_request/methods/auth。
- 已建 pass-through:path=/qianwenai → target=token-plan host,include_subpath=true,cost_per_request=0.2(占位,待填每张真实单价),headers 注入 qianwenai key。id=bb6cc023。
- 实测出图成功(同步,非异步!):POST {网关}/qianwenai/api/v1/services/aigc/multimodal-generation/generation,body=input.messages+parameters,图片在 output.choices[0].message.content[0].image(OSS 签名链接,24h)。1024x1024 PNG 已验证。
- app 模块:scripts/qianwenai_image_example.py(取图路径已按真实响应定稿)。
- 计费:走 cost_per_request 固定按次,计入虚拟 key/user spend,适配图片按张计费。app 调用应用虚拟 key(非 master)+ 带 user。

## 教学换档提示
用户机制已通,偏好"直接给最佳实践 + 为什么",勿再重讲基础。核心交付物是可回看的 reference 卡。

## 真实环境(2026-06-25 连测确认)
- 网关:远程 https://litellm-0w6x.srv1477684.hstgr.cloud/(readiness db connected)。
- 已配模型(真实 model_name):qwen3.7-plus / qwen3.7-max / qwen3.6-plus(通义千问)。
- 现有 key alias=test → 已补预算+限速:max_budget 20 / rpm 120 / tpm 200000(budget_duration 仍 null,不自动重置,需要时手动 reset 或补 --duration)。
- 已建四档预算套餐(均 30d 重置,未绑用户):free(1USD/10/20k)、pro(50USD/120/400k)、elite(200USD/300/1M)、ultra(1000USD/600/2M)。数值为默认阶梯,可单条 upsert 调整。
- 管理 API 可用 token(hash)定位 key,无需明文 sk-(info/update/block 均可)。
- 缓存未启用(/cache/ping 503 Cache not initialized)—— 若要省钱降延迟需在 config 加 cache: true。
- .env 坑:用户曾把 key 写成小写 master_key=,脚本需 LITELLM_MASTER_KEY=(已纠正)。
- 脚本工具集已对真实网关验证可用(health/keys 通)。

## 成本/计费关键发现(2026-06-25)
- qwen 走阿里云 MaaS(token-plan...maas.aliyuncs.com),LiteLLM 无内置价格 → response-cost 恒为 0 → 金额预算永远不触发(只有 rpm/tpm 在拦)。
- 重要更正:模型全是 db_model=True(存 Postgres,非 config 文件)→ 可用 /model/update 运行时改价,【无需碰服务器、无需重启】。已通过 API 给 qwen3.7-plus(2.88/11.52)、qwen3.7-max(12/36)、qwen3.6-plus(占位=plus,待确认)配好元/百万token 价。改价保留了 dashscope/qwen-plan 凭证。实测调用 response-cost 已非 0,u_demo_001 spend 已累计(0.00364608 元,绑 free 档 1 元)。
- Kimi 三模型已修正为独立(用户确认原 model 字段是笔误):k2.5→upstream kimi-k2.5(4.1e-06/1.7e-05)、k2.6→kimi-k2.6(6.5e-06/2.7e-05)、k2.7-code→kimi-k2.7-code(6.5e-06/2.7e-05)。上游 id 均实调 200 验证可路由。provider=moonshot/cred=kimi 保留。k2.5 输出价二级来源有 $2.50/$3.00 两说,取 $2.50→¥17,待用户账单核对。
- 至此全部 8 模型均有价:deepseek×2(内置表)、qwen×3、kimi×3。
- scripts/qwen-models-pricing.yaml 留作 config 写法的参考(若将来改用文件式部署)。
- LiteLLM budget 层【不支持】max_parallel_requests(实测传了仍 null);并发限制只能配在 key 或 general_settings 全局。已从 tiers.sh 撤掉该参数。
- 主流分工结论:网关=限速护栏(rpm/tpm)+成本归账+硬上限兜底;面向用户的"每月多少条/积分"配额放产品后端。金额预算别当用户套餐用。

## 演练已创建(可清理)
- 虚拟 key alias=prod-agent(sk-...RKmw,明文曾打印,建议删后重签私密保存)。
- 测试 end-user u_demo_001(绑 free)。

## 待办/待验证
- 国内具体厂商(通义/DeepSeek/智谱/文心)的 model 串与 api_base 需逐个实测,确认后写进 reference/ 与 RESOURCES.md。
