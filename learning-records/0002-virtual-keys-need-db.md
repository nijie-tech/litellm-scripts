# 已掌握:master_key + 虚拟 key + 数据库前提

用户完成第 02 课:起了 Postgres,在 `general_settings` 配 `master_key` + `database_url`,用 master_key 通过 `/key/generate` 签发了带模型白名单/预算/限速的虚拟 key,并验证了护栏拦截。

确立的起点:
- 两层凭证模型(master_key 签发 / virtual key 使用)已内化。
- 关键前提"虚拟 key 必须有 PostgreSQL 落库"已踩明白。
- 已操作过 `/key/generate` 的 models / max_budget / rpm_limit 参数。

含义:`general_settings` 抽屉打通,可进入 `router_settings`(负载均衡 + fallback)。后续若教 user/team 分层预算,可直接在虚拟 key 基础上扩展,无需回顾。
