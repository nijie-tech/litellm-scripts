#!/usr/bin/env bash
# health.sh — 网关健康检查与运维探针
# 依赖:lib.sh。部分探针无需鉴权,/health 与 /metrics 需 master_key。
#
# 用法:
#   ./health.sh            # 跑全部检查(推荐)
#   ./health.sh live       # GET /health/liveliness  (无需鉴权)
#   ./health.sh ready      # GET /health/readiness   (无需鉴权,含 DB 状态)
#   ./health.sh models     # GET /health            (逐个模型实连测试,需鉴权,可能较慢)
#   ./health.sh cache      # GET /cache/ping         (缓存连通性)
#   ./health.sh metrics    # GET /metrics            (Prometheus 指标,截取前几十行)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() { print_doc "${BASH_SOURCE[0]}"; exit "${1:-0}"; }

c_live()    { info "liveliness:"; api_noauth /health/liveliness; }
c_ready()   { info "readiness:";  api_noauth /health/readiness; }
c_models()  { info "模型实连测试(/health):"; pretty "$(api GET /health)"; }
c_cache()   { info "缓存 ping(/cache/ping):"; pretty "$(api GET /cache/ping)"; }
c_metrics() {
  info "Prometheus 指标(/metrics 前 40 行):"
  curl -sS "${LITELLM_BASE_URL%/}/metrics" \
    -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" | head -40
}

c_all() {
  c_live  || warn "liveliness 失败"
  c_ready || warn "readiness 失败"
  c_cache || warn "cache ping 失败(未开缓存则可忽略)"
  ok "基础探针完成。需要逐模型实连测试请跑:./health.sh models"
}

case "${1:-all}" in
  all)     c_all;;
  live)    c_live;;
  ready)   c_ready;;
  models)  c_models;;
  cache)   c_cache;;
  metrics) c_metrics;;
  -h|--help) usage 0;;
  *) die "未知子命令:$1(用 -h 看帮助)";;
esac
