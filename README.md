# litellm-scripts

LiteLLM 网关运维脚本 + 中文语义路由 + 一键测试环境部署。

## 一键起测试环境(交互式引导,推荐)

```bash
git clone https://github.com/nijie-tech/litellm-scripts.git
cd litellm-scripts
./install.sh        # 全程引导:检测依赖→缺啥问装啥→控制台输入 provider key→起服务
```

`install.sh` 会:检测并(经确认)用阿里云源装 docker/jq/curl/openssl → 控制台输入 4 个 provider key(不回显)→ 自动生成 master/salt/PG 密码 → 起容器 → 建中文语义路由 → 冒烟测试。

跑完后:调用方打 `model="smart-router-v1"` 即按中文复杂度自动分流。

### 进阶:非交互方式

已装好 docker 且想手填 .env,可直接用 `./up.sh`(首跑生成 .env 骨架,填好 provider key 再跑一次)。

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
