#!/usr/bin/env bash
# keys.sh — 虚拟 key 发放/查询/吊销
# 依赖:lib.sh、运行中的网关、已设 LITELLM_MASTER_KEY、网关已接 Postgres。
#
# 用法:
#   ./keys.sh generate [--models m1,m2] [--budget USD] [--rpm N] [--tpm N] [--duration 30d] [--alias 名字]
#   ./keys.sh info   <sk-key>
#   ./keys.sh list
#   ./keys.sh update <sk-key|token> [--budget USD] [--rpm N] [--tpm N] [--models m1,m2] [--duration 30d]
#   ./keys.sh block  <sk-key>
#   ./keys.sh unblock <sk-key>
#   ./keys.sh delete <sk-key>[,<sk-key2>...]
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() { print_doc "${BASH_SOURCE[0]}"; exit "${1:-0}"; }

# 把逗号分隔的字符串转成 JSON 数组:csv_to_json_array "a,b" -> ["a","b"]
csv_to_json_array() {
  local IFS=','; local out="" item
  for item in $1; do out+="\"${item}\","; done
  printf '[%s]' "${out%,}"
}

cmd_generate() {
  local models="" budget="" rpm="" tpm="" duration="" alias=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --models)   models="$2"; shift 2;;
      --budget)   budget="$2"; shift 2;;
      --rpm)      rpm="$2"; shift 2;;
      --tpm)      tpm="$2"; shift 2;;
      --duration) duration="$2"; shift 2;;
      --alias)    alias="$2"; shift 2;;
      *) die "未知参数:$1";;
    esac
  done
  # 拼 JSON body(只放用户给了的字段)
  local fields=()
  [[ -n "$models" ]]   && fields+=("\"models\": $(csv_to_json_array "$models")")
  [[ -n "$budget" ]]   && fields+=("\"max_budget\": $budget")
  [[ -n "$rpm" ]]      && fields+=("\"rpm_limit\": $rpm")
  [[ -n "$tpm" ]]      && fields+=("\"tpm_limit\": $tpm")
  [[ -n "$duration" ]] && fields+=("\"duration\": \"$duration\"")
  [[ -n "$alias" ]]    && fields+=("\"key_alias\": \"$alias\"")
  local body="{$(IFS=,; echo "${fields[*]}")}"
  info "签发虚拟 key:$body"
  local resp; resp="$(api POST /key/generate "$body")"
  ok "已签发。请妥善保存下面的 key(只显示这一次):"
  pretty "$resp"
}

cmd_update() {
  [[ $# -ge 1 ]] || usage 1
  local key="$1"; shift
  local budget="" rpm="" tpm="" models="" duration=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --budget)   budget="$2"; shift 2;;
      --rpm)      rpm="$2"; shift 2;;
      --tpm)      tpm="$2"; shift 2;;
      --models)   models="$2"; shift 2;;
      --duration) duration="$2"; shift 2;;
      *) die "未知参数:$1";;
    esac
  done
  local fields=("\"key\": \"$key\"")
  [[ -n "$budget" ]]   && fields+=("\"max_budget\": $budget")
  [[ -n "$rpm" ]]      && fields+=("\"rpm_limit\": $rpm")
  [[ -n "$tpm" ]]      && fields+=("\"tpm_limit\": $tpm")
  [[ -n "$models" ]]   && fields+=("\"models\": $(csv_to_json_array "$models")")
  [[ -n "$duration" ]] && fields+=("\"duration\": \"$duration\"")
  local body="{$(IFS=,; echo "${fields[*]}")}"
  info "更新 key:$body"
  pretty "$(api POST /key/update "$body")"
  ok "已更新"
}

cmd_info()    { [[ $# -ge 1 ]] || usage 1; pretty "$(api GET "/key/info?key=$1")"; }
cmd_list()    { pretty "$(api GET "/key/list?return_full_object=true")"; }
cmd_block()   { [[ $# -ge 1 ]] || usage 1; pretty "$(api POST /key/block   "{\"key\":\"$1\"}")"; ok "已禁用 $1"; }
cmd_unblock() { [[ $# -ge 1 ]] || usage 1; pretty "$(api POST /key/unblock "{\"key\":\"$1\"}")"; ok "已启用 $1"; }
cmd_delete()  { [[ $# -ge 1 ]] || usage 1; pretty "$(api POST /key/delete  "{\"keys\":$(csv_to_json_array "$1")}")"; ok "已删除 $1"; }

case "${1:-}" in
  generate) shift; cmd_generate "$@";;
  info)     shift; cmd_info "$@";;
  update)   shift; cmd_update "$@";;
  list)     shift; cmd_list;;
  block)    shift; cmd_block "$@";;
  unblock)  shift; cmd_unblock "$@";;
  delete)   shift; cmd_delete "$@";;
  -h|--help|"") usage 0;;
  *) die "未知子命令:$1(用 -h 看帮助)";;
esac
