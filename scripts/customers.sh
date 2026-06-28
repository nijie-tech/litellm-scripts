#!/usr/bin/env bash
# customers.sh — 终端用户(end-user)管理:绑套餐 / 查花费 / 封禁解封
# end-user = 你 agent 背后的 C 端个人;调用时通过请求体的 "user" 字段标识。
# 依赖:lib.sh、网关已接 Postgres、已用 tiers.sh 建好套餐。
#
# 用法:
#   ./customers.sh add    <user_id> --tier <budget_id>   # 绑定套餐
#   ./customers.sh info   <user_id>                       # 查花费/用量
#   ./customers.sh block  <user_id>[,<user_id2>...]
#   ./customers.sh unblock <user_id>[,<user_id2>...]
#
# 提示:你的 agent 调用网关时务必带上  "user": "<user_id>"  否则花费记不到人头。
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() { print_doc "${BASH_SOURCE[0]}"; exit "${1:-0}"; }

csv_to_json_array() {
  local IFS=','; local out="" item
  for item in $1; do out+="\"${item}\","; done
  printf '[%s]' "${out%,}"
}

cmd_add() {
  [[ $# -ge 1 ]] || usage 1
  local uid="$1"; shift
  local tier=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tier) tier="$2"; shift 2;;
      *) die "未知参数:$1";;
    esac
  done
  local fields=("\"user_id\": \"$uid\"")
  [[ -n "$tier" ]] && fields+=("\"budget_id\": \"$tier\"")
  local body="{$(IFS=,; echo "${fields[*]}")}"
  info "登记终端用户:$body"
  pretty "$(api POST /customer/new "$body")"
  ok "用户 $uid 已登记${tier:+(套餐 $tier)}"
}

cmd_info()    { [[ $# -ge 1 ]] || usage 1; pretty "$(api GET "/customer/info?end_user_id=$1")"; }
cmd_block()   { [[ $# -ge 1 ]] || usage 1; pretty "$(api POST /customer/block   "{\"user_ids\":$(csv_to_json_array "$1")}")"; ok "已封禁 $1"; }
cmd_unblock() { [[ $# -ge 1 ]] || usage 1; pretty "$(api POST /customer/unblock "{\"user_ids\":$(csv_to_json_array "$1")}")"; ok "已解封 $1"; }

case "${1:-}" in
  add)     shift; cmd_add "$@";;
  info)    shift; cmd_info "$@";;
  block)   shift; cmd_block "$@";;
  unblock) shift; cmd_unblock "$@";;
  -h|--help|"") usage 0;;
  *) die "未知子命令:$1(用 -h 看帮助)";;
esac
