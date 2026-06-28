# litellm-scripts

LiteLLM 网关运维脚本 + 中文语义路由 + 一键测试环境部署。

## 一键起测试环境

```bash
git clone https://github.com/nijie-tech/litellm-scripts.git
cd litellm-scripts

./up.sh        # ① 首次:生成 .env(含随机 master/salt),提示填 provider key
# 编辑 scripts/test-deploy/.env,填 DEEPSEEK/MOONSHOT/DASHSCOPE/SILICONFLOW 四个 key
./up.sh        # ② 再跑:起容器 → 等就绪 → 建中文语义路由 → 冒烟测试
```

跑完后:调用方打 `model="smart-router-v1"` 即按中文复杂度自动分流。

> 没装 docker?国内走阿里云源(见 `up.sh` 提示)。镜像拉不动 ghcr.io?在 `scripts/test-deploy/.env` 取消注释 `LITELLM_IMAGE` 换镜像。

## 目录

| 路径 | 说明 |
|---|---|
| `up.sh` | 一键部署入口 |
| `scripts/setup-smart-router.sh` | 部署中文语义路由(auto_router + SiliconFlow embedding) |
| `scripts/smart-router-routes.json` | 路由规则与中文例句(改路由只动这个) |
| `scripts/test-deploy/` | docker-compose(proxy + postgres,无 redis)+ config + 密钥生成 |
| `scripts/keys.sh / tiers.sh / customers.sh / health.sh` | 虚拟 key / 预算档 / end-user / 健康检查 |
| `scripts/auto-router.config.yaml` | 文件式部署的 config.yaml 参考 |
| `scripts/app_side_router_example.py` | 应用层路由示例(另一条技术路线) |

## 安全

- 所有 `.env` 已被 `.gitignore` 忽略,不入库;仓库只含 `.env.example` 占位。
- `LITELLM_SALT_KEY` 一旦设定有数据后不可改(用于加密入库凭证)。
