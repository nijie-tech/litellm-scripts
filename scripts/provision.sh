#!/usr/bin/env bash
# provision.sh — 一键初始化网关运营配置
# 编排:健康检查 → 建套餐(free/pro)→ 给 agent 应用签发一把虚拟 key。
# 适合首次部署后或在 CI 里跑。幂等性取决于各 API(套餐为 upsert,key 每次新签)。
#
# 用法:
#   ./provision.sh                 # 全流程
#   ./provision.sh --skip-key      # 只建套餐,不签新 key
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/lib.sh"

SKIP_KEY=0
[[ "${1:-}" == "--skip-key" ]] && SKIP_KEY=1

info "1/3 健康检查..."
bash "${HERE}/health.sh" all || warn "健康检查有告警,请确认网关与 DB 正常后再继续"

info "2/3 创建预算套餐 free / pro ..."
bash "${HERE}/tiers.sh" seed

if [[ "$SKIP_KEY" -eq 0 ]]; then
  info "3/3 为 agent 应用签发虚拟 key(限主力+备用模型,月预算 $50)..."
  bash "${HERE}/keys.sh" generate \
    --models chat-default,chat-cn \
    --budget 50 --rpm 200 --duration 30d \
    --alias c-end-agent
  warn "请把上面返回的 key 存进你 agent 后端的密钥管理,不要硬编码。"
else
  info "3/3 已跳过 key 签发(--skip-key)"
fi

ok "初始化完成。后续运营:"
cat <<'TIP'
  绑用户到套餐:  ./customers.sh add  <user_id> --tier free
  查某用户花费:  ./customers.sh info <user_id>
  封禁滥用用户:  ./customers.sh block <user_id>
  查看 key 列表:  ./keys.sh list
  指标大盘:      ./health.sh metrics
TIP
