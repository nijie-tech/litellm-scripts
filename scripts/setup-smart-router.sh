#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════
# setup-smart-router.sh — 在【任意】LiteLLM 网关上一键部署"中文语义路由"
#                          (LiteLLM 原生 auto_router + 多语 embedding)
#
# 自包含:不依赖其他脚本;只需 bash + curl + jq。env 驱动,绝不写死 key。
# 适合迁移:把本文件 + smart-router-routes.json 拷到新环境,设好 env 即可跑。
#
# 必填环境变量(可写进同目录 .env,脚本会自动加载):
#   LITELLM_BASE_URL      新网关地址,如 https://your-gw.example.com
#   LITELLM_MASTER_KEY    网关 master key
#   SILICONFLOW_API_KEY   SiliconFlow key(embedding 用)
#
# 可选(均有默认):
#   ROUTER_NAME=smart-router-v1   路由器对外名(改配置请升版本号,见末尾"运维规则")
#   EMBED_NAME=zh-embed           embedding 部署名
#   DEFAULT_MODEL=qwen3.7-plus    没命中阈值时兜底(必须是网关已存在的 model_name)
#   EMBED_MODEL=openai/BAAI/bge-m3            embedding 模型(openai/ 兼容通道)
#   EMBED_API_BASE=https://api.siliconflow.cn/v1
#   ROUTES_FILE=./smart-router-routes.json   路由规则数据
#
# 用法:
#   ./setup-smart-router.sh            # 预检 + 部署 + 冒烟测试
#   ./setup-smart-router.sh --check    # 只预检,不写任何东西
#   ./setup-smart-router.sh --test     # 只对已部署的 ROUTER_NAME 跑冒烟测试
# ════════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── 加载 .env(脚本目录 → 当前目录) ──
_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _f in "${_DIR}/.env" "${PWD}/.env"; do
  [[ -f "$_f" ]] && { set -a; . "$_f"; set +a; break; }
done

# ── 默认值 ──
ROUTER_NAME="${ROUTER_NAME:-smart-router-v1}"
EMBED_NAME="${EMBED_NAME:-zh-embed}"
DEFAULT_MODEL="${DEFAULT_MODEL:-qwen3.7-plus}"
EMBED_MODEL="${EMBED_MODEL:-openai/BAAI/bge-m3}"
EMBED_API_BASE="${EMBED_API_BASE:-https://api.siliconflow.cn/v1}"
ROUTES_FILE="${ROUTES_FILE:-${_DIR}/smart-router-routes.json}"

# ── 输出 ──
if [[ -t 1 ]]; then R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; D=$'\033[2m'; X=$'\033[0m'; else R= G= Y= D= X=; fi
info(){ printf '%s\n' "${D}» $*${X}" >&2; }
ok(){   printf '%s\n' "${G}✓ $*${X}" >&2; }
warn(){ printf '%s\n' "${Y}! $*${X}" >&2; }
die(){  printf '%s\n' "${R}✗ $*${X}" >&2; exit 1; }

# ── curl 封装:_api METHOD PATH [BODY] → stdout 响应体;非 2xx 退出 ──
_api(){
  local m="$1" p="$2" b="${3:-}" tmp code
  tmp="$(mktemp)"
  if [[ -n "$b" ]]; then
    code="$(curl -sS -o "$tmp" -w '%{http_code}' -X "$m" "${LITELLM_BASE_URL%/}${p}" \
      -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" -H "Content-Type: application/json" -d "$b")"
  else
    code="$(curl -sS -o "$tmp" -w '%{http_code}' -X "$m" "${LITELLM_BASE_URL%/}${p}" \
      -H "Authorization: Bearer ${LITELLM_MASTER_KEY}")"
  fi
  local resp; resp="$(cat "$tmp")"; rm -f "$tmp"
  [[ "$code" -ge 200 && "$code" -lt 300 ]] || { warn "${m} ${p} → HTTP ${code}"; echo "$resp" >&2; return 1; }
  printf '%s' "$resp"
}

# ════════════════════════ 预检 ════════════════════════
MODEL_INFO=""   # 缓存 /model/info
preflight(){
  command -v curl >/dev/null || die "缺 curl"
  command -v jq   >/dev/null || die "缺 jq"
  [[ -n "${LITELLM_BASE_URL:-}"   ]] || die "未设 LITELLM_BASE_URL"
  [[ -n "${LITELLM_MASTER_KEY:-}" ]] || die "未设 LITELLM_MASTER_KEY"
  [[ -n "${SILICONFLOW_API_KEY:-}" ]] || die "未设 SILICONFLOW_API_KEY(embedding 需要)"
  [[ -f "$ROUTES_FILE" ]] || die "找不到路由规则文件:$ROUTES_FILE"
  jq -e . "$ROUTES_FILE" >/dev/null 2>&1 || die "路由规则文件不是合法 JSON:$ROUTES_FILE"

  info "探活 ${LITELLM_BASE_URL} ..."
  local ready; ready="$(curl -sS "${LITELLM_BASE_URL%/}/health/readiness" || true)"
  echo "$ready" | jq -e '.status=="healthy"' >/dev/null 2>&1 \
    && ok "网关存活,DB=$(echo "$ready" | jq -r '.db // "?"')" \
    || warn "readiness 异常或不可达:$ready"

  info "校验 master key 并拉取模型清单 ..."
  MODEL_INFO="$(_api GET /model/info)" || die "master key 无效或 /model/info 失败"
  local names; names="$(echo "$MODEL_INFO" | jq -r '.data[].model_name')"
  ok "master key 有效,网关现有 $(echo "$names" | grep -c . ) 个模型"

  # 校验路由目标模型 + 兜底模型 都已存在(语义路由的 route.name 必须能落地)
  info "校验路由目标模型是否都已在新网关 ..."
  local missing=0 tgt
  for tgt in $(jq -r '.routes[].name' "$ROUTES_FILE") "$DEFAULT_MODEL"; do
    if echo "$names" | grep -qx "$tgt"; then
      printf '   %s %s\n' "${G}✓${X}" "$tgt" >&2
    else
      printf '   %s %s  ← 网关里没有这个 model_name\n' "${R}✗${X}" "$tgt" >&2; missing=1
    fi
  done
  [[ "$missing" -eq 0 ]] || die "上面缺失的目标模型请先在新网关配好,再跑本脚本(route.name 必须 = 已存在 model_name)。"
  ok "预检通过。"
}

# ════════════════════════ 删除同名(幂等) ════════════════════════
_delete_by_name(){
  local name="$1" id
  for id in $(echo "$MODEL_INFO" | jq -r --arg n "$name" '.data[]|select(.model_name==$n)|.model_info.id'); do
    info "删除旧 $name id=$id"
    _api POST /model/delete "$(jq -nc --arg id "$id" '{id:$id}')" >/dev/null || true
  done
}

# ════════════════════════ 部署 ════════════════════════
provision(){
  # 1) embedding 部署(openai/ 兼容通道接 SiliconFlow,key 取自 env、不写死)
  _delete_by_name "$EMBED_NAME"
  local emb
  emb="$(jq -nc --arg n "$EMBED_NAME" --arg m "$EMBED_MODEL" --arg b "$EMBED_API_BASE" --arg k "$SILICONFLOW_API_KEY" \
    '{model_name:$n, litellm_params:{model:$m, api_base:$b, api_key:$k}, model_info:{mode:"embedding"}}')"
  _api POST /model/new "$emb" | jq -r '"✓ embedding: \(.model_name) id=\(.model_info.id)"' >&2

  # 2) 路由器:auto_router_config 从 routes 文件内联(route.name = 目标 model_name)
  _delete_by_name "$ROUTER_NAME"
  local cfg body
  cfg="$(jq -c '{routes: [.routes[] | {name, score_threshold, utterances}]}' "$ROUTES_FILE")"
  body="$(jq -nc --arg n "$ROUTER_NAME" --arg cfg "$cfg" --arg dm "$DEFAULT_MODEL" --arg emb "$EMBED_NAME" \
    '{model_name:$n, litellm_params:{model:("auto_router/"+$n), auto_router_config:$cfg, auto_router_default_model:$dm, auto_router_embedding_model:$emb}}')"
  _api POST /model/new "$body" | jq -r '"✓ router:    \(.model_name) id=\(.model_info.id)"' >&2
  ok "部署完成。调用方打 model=\"$ROUTER_NAME\" 即自动中文分流。"
}

# ════════════════════════ 冒烟测试 ════════════════════════
SMOKE=(
  "在不在呀无聊死了陪我聊会儿"
  "帮我把这句翻译成法语"
  "我这个Go协程一跑就panic帮我看看"
  "用numpy写个矩阵乘法"
  "这个SQL查询太慢了怎么优化"
  "设计一个支持百万QPS的实时排行榜要考虑热点key和数据倾斜"
)
smoke(){
  info "冒烟测试 ROUTER_NAME=$ROUTER_NAME(首条含冷启动,稍慢)"
  local map; map="$(_api GET /model/info | jq -r '.data[]|"\(.model_info.id)\t\(.model_name)"')"
  local q hdr mid name
  for q in "${SMOKE[@]}"; do
    hdr="$(curl -sS -D - -o /dev/null -X POST "${LITELLM_BASE_URL%/}/v1/chat/completions" \
      -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" -H "Content-Type: application/json" \
      -d "$(jq -nc --arg q "$q" --arg m "$ROUTER_NAME" '{model:$m,messages:[{role:"user",content:$q}],max_tokens:1}')")"
    mid="$(echo "$hdr" | grep -i '^x-litellm-model-id:' | head -1 | cut -d' ' -f2- | tr -d '\r')"
    name="$(echo "$map" | awk -F'\t' -v id="$mid" '$1==id{print $2}')"
    printf '  %-34s → %s\n' "${q:0:32}" "${name:-未知}" >&2
  done
}

# ════════════════════════ 入口 ════════════════════════
case "${1:-all}" in
  --check) preflight ;;
  --test)  smoke ;;
  all|"")  preflight; provision; smoke
           echo >&2
           warn "运维规则:路由配置变更后,运行进程会缓存旧 routelayer 不刷新。"
           warn "  → 改 routes/阈值后,把 ROUTER_NAME 升版本号(如 smart-router-v2)重跑,或 reload 网关。"
           warn "安全:embedding key 现存于网关 DB(取自你的 env);生产建议改 os.environ 引用并轮换。"
           ;;
  -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
  *) die "未知参数:$1(用 -h 看帮助)" ;;
esac
