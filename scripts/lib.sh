#!/usr/bin/env bash
# lib.sh — LiteLLM 网关运维脚本共享库
# 被 keys.sh / tiers.sh / customers.sh / health.sh / provision.sh 引用。
# 不直接执行。
#
# 约定:所有管理 API 都需要 master_key;连接信息从环境变量或同目录 .env 读取。
set -euo pipefail

# ── 加载 .env(按顺序找:脚本目录 → 上级目录 → 当前工作目录,取首个命中) ──
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _envf in "${_LIB_DIR}/.env" "${_LIB_DIR}/../.env" "${PWD}/.env"; do
  if [[ -f "$_envf" ]]; then
    # shellcheck disable=SC1091
    set -a; source "$_envf"; set +a
    LITELLM_ENV_FILE="$_envf"
    break
  fi
done

# ── 必需配置 ──
LITELLM_BASE_URL="${LITELLM_BASE_URL:-http://0.0.0.0:4000}"
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-}"

# ── 颜色输出 ──
if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
  C_RED=''; C_GRN=''; C_YEL=''; C_DIM=''; C_RST=''
fi
info() { printf '%s\n' "${C_DIM}» $*${C_RST}" >&2; }
ok()   { printf '%s\n' "${C_GRN}✓ $*${C_RST}" >&2; }
warn() { printf '%s\n' "${C_YEL}! $*${C_RST}" >&2; }
die()  { printf '%s\n' "${C_RED}✗ $*${C_RST}" >&2; exit 1; }

# ── 依赖与前置检查 ──
need_master() {
  [[ -n "$LITELLM_MASTER_KEY" ]] || die "未设置 LITELLM_MASTER_KEY。请复制 .env.example 为 .env 并填写,或 export 该变量。"
}

# pretty <json>:有 jq 用 jq,否则退回 python3,再否则原样输出
pretty() {
  local data="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$data" | jq . 2>/dev/null || printf '%s\n' "$data"
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$data" | python3 -m json.tool 2>/dev/null || printf '%s\n' "$data"
  else
    printf '%s\n' "$data"
  fi
}

# 从 json 取某个顶层字段(优先 jq,退回 python3)。用法:json_get <json> <key>
json_get() {
  local data="$1" key="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$data" | jq -r ".${key} // empty" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$data" | python3 -c "import sys,json;print(json.load(sys.stdin).get('${key}','') or '')" 2>/dev/null
  fi
}

# api <METHOD> <PATH> [JSON_BODY]
# 带 master_key 调管理 API;非 2xx 时打印响应体并退出。stdout 仅输出响应体。
api() {
  need_master
  local method="$1" path="$2" body="${3:-}"
  local url="${LITELLM_BASE_URL%/}${path}"
  local tmp http
  tmp="$(mktemp)"
  if [[ -n "$body" ]]; then
    http="$(curl -sS -o "$tmp" -w '%{http_code}' -X "$method" "$url" \
      -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
      -H "Content-Type: application/json" \
      -d "$body")"
  else
    http="$(curl -sS -o "$tmp" -w '%{http_code}' -X "$method" "$url" \
      -H "Authorization: Bearer ${LITELLM_MASTER_KEY}")"
  fi
  local resp; resp="$(cat "$tmp")"; rm -f "$tmp"
  if [[ "$http" -lt 200 || "$http" -ge 300 ]]; then
    warn "${method} ${path} → HTTP ${http}"
    pretty "$resp" >&2
    return 1
  fi
  printf '%s' "$resp"
}

# 打印脚本头部连续注释块作为帮助(去掉 # 前缀),从第 2 行到首个非注释行。
# 用法:usage() { print_doc "${BASH_SOURCE[0]}"; exit "${1:-0}"; }
print_doc() {
  awk 'NR==1{next} /^#/{sub(/^# ?/,"");print;next} {exit}' "$1"
}

# 无需鉴权的 GET(健康探针用)。api_noauth <PATH>
api_noauth() {
  local path="$1"
  local url="${LITELLM_BASE_URL%/}${path}"
  curl -sS -w '\n[HTTP %{http_code}]\n' "$url"
}
