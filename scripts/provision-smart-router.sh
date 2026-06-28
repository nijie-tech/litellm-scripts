#!/usr/bin/env bash
# provision-smart-router.sh — 在活网关上建/更新"中文语义路由"(LiteLLM 原生 auto_router)
# 依赖:lib.sh(读 .env 里的 LITELLM_BASE_URL / LITELLM_MASTER_KEY)。
#
# 这套是 db-model + 管理 API 驱动(改模型不重启),所以"部署"= 跑这个脚本。
#
# 必填环境变量(写进同目录 .env 或 export):
#   SILICONFLOW_API_KEY   SiliconFlow key(embedding 用;生产应配在网关进程的 os.environ)
#
# 用法:
#   ./provision-smart-router.sh                 # 建 zh-embed + smart-router(默认名)
#   ROUTER_NAME=smart-router-v2 ./provision-smart-router.sh   # 换名(调优后避开旧实例缓存)
#
# ⚠️ 坑:改已存在的 auto_router 配置,运行进程会缓存旧 routelayer 不生效。
#        重新调优 utterances/阈值时,用 ROUTER_NAME 换个新名,或 reload 网关。
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ROUTER_NAME="${ROUTER_NAME:-smart-router}"
EMBED_NAME="zh-embed"
DEFAULT_MODEL="qwen3.7-plus"   # 没命中阈值时兜底(必须是 model_list 里已存在的名)

[[ -n "${SILICONFLOW_API_KEY:-}" ]] || die "未设置 SILICONFLOW_API_KEY(embedding 需要)。"
need_master

# ── 幂等:按名删除旧的同名部署 ──
delete_by_name() {
  local name="$1" ids id
  ids="$(api GET /model/info | jq -r --arg n "$name" '.data[]|select(.model_name==$n)|.model_info.id')"
  for id in $ids; do
    info "删除旧 $name id=$id"
    api POST /model/delete "$(jq -nc --arg id "$id" '{id:$id}')" >/dev/null || true
  done
}

# ── 1) 中文 embedding 部署:SiliconFlow bge-m3,走 openai/ 兼容通道(LiteLLM 无原生 siliconflow provider) ──
provision_embed() {
  delete_by_name "$EMBED_NAME"
  local body
  body="$(jq -nc --arg k "$SILICONFLOW_API_KEY" --arg n "$EMBED_NAME" '{
    model_name: $n,
    litellm_params: { model: "openai/BAAI/bge-m3", api_base: "https://api.siliconflow.cn/v1", api_key: $k },
    model_info: { mode: "embedding" }
  }')"
  api POST /model/new "$body" | jq -r '"✓ embedding: \(.model_name) id=\(.model_info.id)"'
}

# ── 2) 语义路由器:route.name = 目标 model_name;utterances 写中文真实说法 ──
#    例句数不再受 DashScope batch≤10 限制(SiliconFlow batch 8192)。每档 8 条,可继续加。
router_config() {
  jq -nc '{routes:[
    {name:"deepseek/deepseek-v4-flash", score_threshold:0.30, utterances:[
      "你好呀,在吗","嗯嗯好的谢谢啦","今天天气怎么样","哈喽在干嘛呢","给我讲个笑话呗","晚安啦","你叫什么名字","随便聊聊天"]},
    {name:"qwen3.7-plus", score_threshold:0.30, utterances:[
      "帮我把这段话翻译成英文","总结一下这篇文章的要点","解释下什么是HTTP缓存","用三句话说说区块链是啥","帮我润色这段文案让它更通顺","推荐几本入门机器学习的书","这个英文单词怎么用造个句","帮我列个周末出游计划"]},
    {name:"kimi-k2.7-code", score_threshold:0.30, utterances:[
      "帮我写个线程安全的LRU缓存","这段代码为什么报空指针异常","用Python实现快速排序并加注释","帮我重构这个函数太长了","写个正则匹配邮箱地址","这个SQL查询怎么优化","解释下这段报错栈是什么意思","给这个接口写个单元测试","用numpy实现矩阵乘法","用pandas处理这个表格"]},
    {name:"qwen3.7-max", score_threshold:0.30, utterances:[
      "设计一个支持千万级用户的短链系统并分析分库分表与缓存穿透的取舍","证明1到n的立方和等于求和的平方并给出归纳法推导","权衡用Kafka还是RabbitMQ从一致性和吞吐角度详细分析","分析微服务和单体架构各自的利弊和适用场景","推导这个动态规划的状态转移方程并分析时间复杂度","从第一性原理分析为什么分布式系统难以同时满足CAP","给一套完整的高并发秒杀系统设计方案并论证每个取舍","比较Paxos和Raft共识算法的优劣与适用场景"]}
  ]}'
}

provision_router() {
  delete_by_name "$ROUTER_NAME"
  local cfg body
  cfg="$(router_config)"
  body="$(jq -nc --arg n "$ROUTER_NAME" --arg cfg "$cfg" --arg dm "$DEFAULT_MODEL" '{
    model_name: $n,
    litellm_params: {
      model: ("auto_router/" + $n),
      auto_router_config: $cfg,
      auto_router_default_model: $dm,
      auto_router_embedding_model: "zh-embed"
    }
  }')"
  api POST /model/new "$body" | jq -r '"✓ router: \(.model_name) id=\(.model_info.id)"'
}

provision_embed
provision_router
ok "完成。调用方打 model=\"$ROUTER_NAME\" 即可自动中文分流;落点看响应头 x-litellm-model-id。"
