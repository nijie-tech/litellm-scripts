#!/usr/bin/env bash
# tiers.sh — 预算套餐(budget)管理:给 C 端做免费/付费分层
# 一个 budget 可被多个 customer(end-user)绑定。
# 依赖:lib.sh、网关已接 Postgres。
#
# 用法:
#   ./tiers.sh create <budget_id> [--budget 金额] [--rpm N] [--tpm N] [--duration 30d]
#   注:并发上限(max_parallel_requests)budget 层不支持,需配在 key 或 general_settings 全局。
#   ./tiers.sh list
#   ./tiers.sh info <budget_id>
#   ./tiers.sh seed        # 一键创建两个示例套餐:free / pro
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() { print_doc "${BASH_SOURCE[0]}"; exit "${1:-0}"; }

cmd_create() {
  [[ $# -ge 1 ]] || usage 1
  local id="$1"; shift
  local budget="" rpm="" tpm="" duration=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --budget)   budget="$2"; shift 2;;
      --rpm)      rpm="$2"; shift 2;;
      --tpm)      tpm="$2"; shift 2;;
      --duration) duration="$2"; shift 2;;
      *) die "未知参数:$1";;
    esac
  done
  local fields=("\"budget_id\": \"$id\"")
  [[ -n "$budget" ]]   && fields+=("\"max_budget\": $budget")
  [[ -n "$rpm" ]]      && fields+=("\"rpm_limit\": $rpm")
  [[ -n "$tpm" ]]      && fields+=("\"tpm_limit\": $tpm")
  [[ -n "$duration" ]] && fields+=("\"budget_duration\": \"$duration\"")
  local body="{$(IFS=,; echo "${fields[*]}")}"
  info "创建套餐:$body"
  pretty "$(api POST /budget/new "$body")"
  ok "套餐 $id 已创建/更新"
}

cmd_list() { pretty "$(api GET /budget/list)"; }
cmd_info() { [[ $# -ge 1 ]] || usage 1; pretty "$(api POST /budget/info "{\"budgets\":[\"$1\"]}")"; }

# seed:产品方付费场景的四档阶梯套餐(数值按需改;均 30 天重置)
# 档位:free < pro < elite < ultra,预算/限速逐级上升。
cmd_seed() {
  info "创建 free  套餐(月预算 1 元)..."
  cmd_create free  --budget 1    --rpm 10  --tpm 20000   --duration 30d
  info "创建 pro   套餐(月预算 50 元)..."
  cmd_create pro   --budget 50   --rpm 120 --tpm 400000  --duration 30d
  info "创建 elite 套餐(月预算 200 元)..."
  cmd_create elite --budget 200  --rpm 300 --tpm 1000000 --duration 30d
  info "创建 ultra 套餐(月预算 1000 元)..."
  cmd_create ultra --budget 1000 --rpm 600 --tpm 2000000 --duration 30d
  ok "四档套餐就绪:free / pro / elite / ultra。用 customers.sh 把用户绑上去。"
}

case "${1:-}" in
  create) shift; cmd_create "$@";;
  list)   shift; cmd_list;;
  info)   shift; cmd_info "$@";;
  seed)   shift; cmd_seed;;
  -h|--help|"") usage 0;;
  *) die "未知子命令:$1(用 -h 看帮助)";;
esac
