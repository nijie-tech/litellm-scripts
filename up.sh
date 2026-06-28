#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════
# up.sh — 一键拉起 LiteLLM 测试环境(proxy + Postgres)并部署中文语义路由
#
# 在服务器上:
#   git clone https://github.com/nijie-tech/litellm-scripts.git
#   cd litellm-scripts
#   ./up.sh            # 首次:生成 .env(含随机 master/salt)并提示填 provider key
#   # 编辑 scripts/test-deploy/.env 填 4 个 provider key
#   ./up.sh            # 再跑:起容器 → 等就绪 → 建语义路由 → 冒烟测试
#
# 幂等可重复跑。需要:docker(含 compose 插件)、jq、curl、openssl。
# ════════════════════════════════════════════════════════════════════════
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="$ROOT/scripts/test-deploy"
ENVF="$DEPLOY/.env"

G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; X=$'\033[0m'
say(){ printf '%s\n' "$*"; }
ok(){  printf '%s\n' "${G}✓ $*${X}"; }
warn(){ printf '%s\n' "${Y}! $*${X}"; }
die(){ printf '%s\n' "${R}✗ $*${X}"; exit 1; }

# ── 0. 工具检查 ──
for t in jq curl openssl; do command -v "$t" >/dev/null || die "缺 $t,请先安装"; done
command -v docker >/dev/null || die "缺 docker。参考 README 装法(国内走阿里云源)"
DK="docker"; docker info >/dev/null 2>&1 || DK="sudo docker"   # 不在 docker 组则用 sudo
$DK compose version >/dev/null 2>&1 || die "缺 docker compose 插件"

# ── 1. 首次:scaffold .env,注入随机 master/salt/PG 密码,提示填 provider key ──
if [[ ! -f "$ENVF" ]]; then
  cp "$DEPLOY/.env.example" "$ENVF"
  MK="sk-$(openssl rand -hex 32)"; SK="sk-$(openssl rand -hex 32)"; PG="$(openssl rand -hex 16)"
  sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$PG|"     "$ENVF"
  sed -i "s|^LITELLM_MASTER_KEY=.*|LITELLM_MASTER_KEY=$MK|"   "$ENVF"
  sed -i "s|^LITELLM_SALT_KEY=.*|LITELLM_SALT_KEY=$SK|"       "$ENVF"
  ok "已生成 $ENVF(随机 master / salt / PG 密码)"
  warn "下一步:编辑该文件,填入 4 个 provider key:"
  say  "    DEEPSEEK_API_KEY  MOONSHOT_API_KEY  DASHSCOPE_API_KEY  SILICONFLOW_API_KEY"
  say  "  (国内拉不动镜像?顺手取消注释 LITELLM_IMAGE 换镜像)"
  say  "  填好后再次运行:./up.sh"
  exit 0
fi

# ── 2. 校验 provider key 已填 ──
set -a; . "$ENVF"; set +a
miss=()
for k in DEEPSEEK_API_KEY MOONSHOT_API_KEY DASHSCOPE_API_KEY SILICONFLOW_API_KEY; do
  [[ -n "${!k:-}" ]] || miss+=("$k")
done
if [[ ${#miss[@]} -ne 0 ]]; then
  warn "以下 key 未填,对应模型/路由将不可用(可后续补到 $ENVF):${miss[*]}"
  [[ -n "${SILICONFLOW_API_KEY:-}" ]] || die "SILICONFLOW_API_KEY 是语义路由必需项,必须填。"
  [[ -n "${DASHSCOPE_API_KEY:-}" ]]   || die "DASHSCOPE_API_KEY 缺失:默认兜底模型 qwen3.7-plus 用它,必须填。"
fi

# ── 3. 起容器 ──
say "拉起容器(proxy + postgres)..."
( cd "$DEPLOY" && $DK compose up -d )

# ── 4. 等网关就绪(首次含建表,稍久) ──
printf '等网关就绪'
ready=0
for _ in $(seq 1 60); do
  if curl -fsS http://localhost:4000/health/readiness 2>/dev/null | grep -q '"db":"connected"'; then ready=1; break; fi
  printf '.'; sleep 3
done
echo
[[ "$ready" -eq 1 ]] || die "网关 60×3s 内未就绪。查日志:$DK compose -f $DEPLOY/docker-compose.yml logs litellm"
ok "网关就绪(db connected)"

# ── 5. 生成 scripts/.env(setup 脚本的客户端环境,单一来源派生) ──
cat > "$ROOT/scripts/.env" <<EOF
LITELLM_BASE_URL=http://localhost:4000
LITELLM_MASTER_KEY=$LITELLM_MASTER_KEY
SILICONFLOW_API_KEY=$SILICONFLOW_API_KEY
EOF
ok "已生成 scripts/.env"

# ── 6. 建中文语义路由 + 冒烟测试 ──
say "部署中文语义路由..."
( cd "$ROOT/scripts" && ./setup-smart-router.sh )

echo
ok "全部完成 🎉"
say "  网关:    http://<服务器IP>:4000"
say "  路由器名:smart-router-v1(调用方打这个 model 名即自动中文分流)"
say "  管理:    cd scripts && ./keys.sh / ./tiers.sh / ./customers.sh / ./health.sh"
