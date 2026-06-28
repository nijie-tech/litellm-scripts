#!/usr/bin/env bash
# generate-config.sh — 生成生产级 config.yaml 模板(不覆盖你现有的)
# 默认写到 ./config.best-practice.yaml;你把自己已配好的 model_list 合并进去即可。
#
# 用法:
#   ./generate-config.sh [输出路径]     # 默认 ./config.best-practice.yaml
#   ./generate-config.sh --force [路径]  # 允许覆盖已存在文件
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

FORCE=0
[[ "${1:-}" == "--force" ]] && { FORCE=1; shift; }
OUT="${1:-./config.best-practice.yaml}"

if [[ -e "$OUT" && "$FORCE" -ne 1 ]]; then
  die "已存在 $OUT。加 --force 覆盖,或换个输出路径。(默认不动你现有 config)"
fi

cat > "$OUT" <<'YAML'
# ───────────────────────────────────────────────────────────
# LiteLLM 生产级 config.yaml — C 端 Agent Gateway 最佳实践模板
# 你已配好的 model_list 直接替换/合并下面的占位即可。
# 密钥一律走 os.environ/,切勿写死。
# 详见 reference/best-practices-c-end-gateway.html
# ───────────────────────────────────────────────────────────

model_list:
  # —— 把你已经配好的模型粘到这里;示例:主力 + 国内备用,二者互为 fallback ——
  - model_name: chat-default
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY
      rpm: 500
  - model_name: chat-cn
    litellm_params:
      model: openai/deepseek-chat
      api_base: https://api.deepseek.com
      api_key: os.environ/DEEPSEEK_API_KEY

litellm_settings:
  # 可靠性:C 端少重试、快失败
  num_retries: 2
  request_timeout: 60
  fallbacks: [{"chat-default": ["chat-cn"]}, {"chat-cn": ["chat-default"]}]
  context_window_fallbacks: [{"chat-cn": ["chat-default"]}]
  enable_pre_call_checks: true
  # 成本护栏:单个终端用户累计花费上限(USD),防烧穿
  max_end_user_budget: 5
  # 可观测性
  callbacks: ["prometheus"]
  json_logs: true
  set_verbose: false
  # 缓存(省钱降延迟):用 host/port,不要 redis_url
  cache: true
  cache_params:
    type: redis
    host: os.environ/REDIS_HOST
    port: os.environ/REDIS_PORT
    password: os.environ/REDIS_PASSWORD
    ttl: 600
  # 隐私:第三方追踪只记花费不记对话内容
  turn_off_message_logging: true

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/DATABASE_URL
  alerting: ["slack"]
  proxy_batch_write_at: 60
  database_connection_pool_limit: 10
  allow_requests_on_db_unavailable: true

router_settings:
  routing_strategy: simple-shuffle
  # 多实例时取消注释,让各实例共享路由状态/全局限流:
  # redis_host: os.environ/REDIS_HOST
  # redis_port: os.environ/REDIS_PORT
  # redis_password: os.environ/REDIS_PASSWORD

guardrails:
  - guardrail_name: pii-mask
    litellm_params:
      guardrail: presidio
      mode: pre_call
      pii_entities_config:
        EMAIL_ADDRESS: MASK
        CREDIT_CARD: MASK
        PHONE_NUMBER: MASK
YAML

ok "已生成:$OUT"
info "下一步:把你已配好的模型合并进 model_list,再用以下环境变量启动:"
cat <<'ENV'
  export LITELLM_MODE=PRODUCTION
  export LITELLM_LOG=ERROR
  export LITELLM_MASTER_KEY=sk-...
  export LITELLM_SALT_KEY=sk-...        # 设了别改
  export DATABASE_URL=postgresql://...
  export REDIS_HOST=...  REDIS_PORT=6379  REDIS_PASSWORD=...
  litellm --config <你的最终配置>.yaml
ENV
