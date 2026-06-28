#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════
# install.sh — 交互式引导安装(检测依赖→缺啥问装啥→控制台输入 key→一键起服务)
#
#   git clone https://github.com/nijie-tech/litellm-scripts.git
#   cd litellm-scripts && ./install.sh
#
# 适配国内 Linux 服务器(apt / yum-dnf,docker 走阿里云源)。需以能 sudo 的用户运行。
# ════════════════════════════════════════════════════════════════════════
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="$ROOT/scripts/test-deploy"
ENVF="$DEPLOY/.env"

B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; C=$'\033[36m'; X=$'\033[0m'
say(){ printf '%s\n' "$*"; }
hd(){  printf '\n%s\n' "${B}${C}== $* ==${X}"; }
ok(){  printf '%s\n' "${G}✓ $*${X}"; }
warn(){ printf '%s\n' "${Y}! $*${X}"; }
die(){ printf '%s\n' "${R}✗ $*${X}"; exit 1; }
ask_yn(){ local p="$1" d="${2:-Y}" a; read -rp "$p [$([ "$d" = Y ] && echo 'Y/n' || echo 'y/N')] " a; a="${a:-$d}"; [[ "$a" =~ ^[Yy]$ ]]; }

[[ -t 0 ]] || die "需在交互式终端运行(检测到非 TTY)。"

# ── 提权前缀 ──
SUDO=""; [[ "$(id -u)" -ne 0 ]] && SUDO="sudo"

# ── 识别包管理器 / 发行版 ──
PM=""; OSID=""; DOCKER_OS="ubuntu"
if [[ -r /etc/os-release ]]; then . /etc/os-release; OSID="${ID:-}"; fi
if   command -v apt-get >/dev/null; then PM="apt"
elif command -v dnf     >/dev/null; then PM="dnf"
elif command -v yum     >/dev/null; then PM="yum"
fi
[[ "$OSID" == "debian" ]] && DOCKER_OS="debian"

pm_install(){ # pm_install pkg...
  case "$PM" in
    apt) $SUDO apt-get update -q && $SUDO apt-get install -y "$@" ;;
    dnf) $SUDO dnf install -y "$@" ;;
    yum) $SUDO yum install -y "$@" ;;
    *)   die "认不出包管理器,请手动安装:$*" ;;
  esac
}

# ── 装基础小工具 ──
ensure_tool(){ # ensure_tool cmd pkg
  command -v "$1" >/dev/null && { ok "$1 已安装"; return; }
  warn "缺 $1"
  ask_yn "  是否现在安装 $1?" Y && pm_install "$2" && ok "$1 安装完成" || die "$1 未安装,无法继续"
}

# ── 装 Docker(阿里云源,因 get.docker.com 国内常被重置) ──
install_docker(){
  hd "安装 Docker(阿里云源)"
  case "$PM" in
    apt)
      pm_install ca-certificates curl gnupg
      $SUDO install -m 0755 -d /etc/apt/keyrings
      curl -fsSL "https://mirrors.aliyun.com/docker-ce/linux/${DOCKER_OS}/gpg" | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      $SUDO chmod a+r /etc/apt/keyrings/docker.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/${DOCKER_OS} $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null
      $SUDO apt-get update -q
      $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
      ;;
    yum|dnf)
      pm_install yum-utils 2>/dev/null || pm_install dnf-plugins-core || true
      $SUDO $PM config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo 2>/dev/null \
        || $SUDO yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
      # 阿里云 Linux / Anolis:centos 源用 $releasever 可能匹配不到,固定为 8
      [[ "$OSID" =~ ^(alinux|anolis)$ ]] && $SUDO sed -i 's/\$releasever/8/g' /etc/yum.repos.d/docker-ce.repo
      pm_install docker-ce docker-ce-cli containerd.io docker-compose-plugin
      ;;
    *) die "认不出系统,请手动装 Docker" ;;
  esac
  $SUDO systemctl enable --now docker
  ok "Docker 安装完成"
}

# ════════════════════ 1. 依赖检测 ════════════════════
hd "检测依赖"
ensure_tool curl curl
ensure_tool jq jq
ensure_tool openssl openssl

if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
  ok "Docker + compose 已就绪"
else
  warn "缺 Docker 或 compose 插件"
  ask_yn "  是否现在用阿里云源安装 Docker?" Y && install_docker || die "Docker 未安装,无法继续"
fi

# docker 是否要 sudo
DK="docker"; docker info >/dev/null 2>&1 || DK="$SUDO docker"
if [[ "$DK" == *sudo* ]]; then
  warn "当前用户运行 docker 需 sudo。"
  ask_yn "  把 $USER 加入 docker 组(下次登录免 sudo)?" Y && { $SUDO usermod -aG docker "$USER" || true; warn "已加入,本次仍用 sudo;重新登录后生效。"; }
fi

# ════════════════════ 2. 交互填配置 ════════════════════
hd "网关配置"
if [[ -f "$ENVF" ]] && ! ask_yn "检测到已有 $ENVF,重新配置?" N; then
  ok "沿用现有配置"
else
  cp "$DEPLOY/.env.example" "$ENVF"; chmod 600 "$ENVF"
  # 自动生成、无需用户管
  $SUDO true
  sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -hex 16)|" "$ENVF"
  sed -i "s|^LITELLM_MASTER_KEY=.*|LITELLM_MASTER_KEY=sk-$(openssl rand -hex 32)|" "$ENVF"
  sed -i "s|^LITELLM_SALT_KEY=.*|LITELLM_SALT_KEY=sk-$(openssl rand -hex 32)|" "$ENVF"
  ok "已生成随机 master / salt / Postgres 密码"

  say "下面输入各模型 provider key(输入不回显;直接回车可跳过暂不用的模型):"
  set_kv(){ sed -i "s|^$1=.*|$1=$2|" "$ENVF"; }
  read_secret(){ local name="$1" v; read -rsp "  ${name}: " v; echo; [[ -n "$v" ]] && set_kv "$name" "$v" && ok "${name} 已设(****${v: -4})" || warn "${name} 跳过"; }
  read_secret DEEPSEEK_API_KEY
  read_secret MOONSHOT_API_KEY
  read_secret DASHSCOPE_API_KEY
  read_secret SILICONFLOW_API_KEY
  # DashScope base 允许改默认
  local_base="https://dashscope.aliyuncs.com/compatible-mode/v1"
  read -rp "  DASHSCOPE_BASE(回车用默认 $local_base): " b; set_kv DASHSCOPE_BASE "${b:-$local_base}"

  # ghcr 镜像
  if ask_yn "国内拉取 ghcr.io 常失败,是否启用镜像加速?" Y; then
    if grep -q '^#\? *LITELLM_IMAGE=' "$ENVF"; then
      sed -i 's|^#\? *LITELLM_IMAGE=.*|LITELLM_IMAGE=ghcr.nju.edu.cn/berriai/litellm:main-stable|' "$ENVF"
    else
      echo "LITELLM_IMAGE=ghcr.nju.edu.cn/berriai/litellm:main-stable" >> "$ENVF"
    fi
    ok "已启用 ghcr 镜像(ghcr.nju.edu.cn)"
  fi
fi

# ════════════════════ 3. 起服务 ════════════════════
hd "拉起服务并部署语义路由"
say "交给 up.sh 完成:起容器 → 等就绪 → 建路由 → 冒烟测试 ..."
exec "$ROOT/up.sh"
