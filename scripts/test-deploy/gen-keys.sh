#!/usr/bin/env bash
# gen-keys.sh — 生成 LiteLLM 的 master key 与 salt key(强随机)
#
# 用法:
#   ./gen-keys.sh            # 打印两把 key,手动粘进 .env
#   ./gen-keys.sh >> .env    # 直接追加到当前目录 .env
#
# ⚠️ LITELLM_SALT_KEY 用于加密入库的 provider key;【一旦设定、有数据后就不能改】,
#    改了会导致已加密的凭证无法解密。生成一次,妥善保存。
set -euo pipefail

gen() { openssl rand -hex 32; }   # 32 字节 = 64 位十六进制,无特殊字符,env 安全

echo "LITELLM_MASTER_KEY=sk-$(gen)"
echo "LITELLM_SALT_KEY=sk-$(gen)"
