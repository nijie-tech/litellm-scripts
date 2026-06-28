"""通过 LiteLLM 网关 pass-through 调 qianwenai 图片生成(wan2.7-image)。

前提:已在 LiteLLM Admin UI 配好 pass-through:
  path: /qianwenai  →  target: https://token-plan.cn-beijing.maas.aliyuncs.com
  include_subpath: true,headers 注入上游 key,cost_per_request 设每张单价。

要点:
- qianwenai 图片是 DashScope 原生格式(非 OpenAI /images/generations),所以请求体是
  input.messages + parameters,图片在 choices[0].message.content[0].image。
- wan 模型可能是异步:提交带 X-DashScope-Async: enable → 拿 task_id → 轮询 /tasks/{id}。
- 鉴权两段:本函数用「网关虚拟 key」打网关;网关再注入上游 key 转发给 qianwenai。

⚠️ 异步轮询的字段路径(output.task_id / output.task_status / results)以首次真实响应为准,
   建议先用 sync 试,拿到真实 JSON 再定稿。
"""
from __future__ import annotations
import time
import requests

GATEWAY = "https://litellm-0w6x.srv1477684.hstgr.cloud"   # 你的网关
PASS = f"{GATEWAY}/qianwenai"                              # pass-through 前缀
GEN_PATH = "/api/v1/services/aigc/multimodal-generation/generation"


def _headers(virtual_key: str, async_mode: bool = False) -> dict:
    h = {
        "Authorization": f"Bearer {virtual_key}",   # 网关虚拟 key(限额/计费/日志)
        "Content-Type": "application/json",
    }
    if async_mode:
        h["X-DashScope-Async"] = "enable"
    return h


def _body(prompt: str, model: str, size: str) -> dict:
    return {
        "model": model,
        "input": {"messages": [{"role": "user", "content": [{"text": prompt}]}]},
        "parameters": {"size": size, "n": 1},
    }


def _extract_image(resp: dict) -> str | None:
    """从同步响应里取图片 URL(实测路径):output.choices[0].message.content[0].image。
    图片 URL 为阿里云 OSS 签名链接,24 小时有效。"""
    try:
        return resp["output"]["choices"][0]["message"]["content"][0]["image"]
    except (KeyError, IndexError, TypeError):
        return None


def generate_image(
    prompt: str,
    virtual_key: str,
    *,
    model: str = "wan2.7-image",
    size: str = "1024*1024",
    user_id: str | None = None,
    poll_timeout: int = 60,
) -> str:
    """生成一张图,返回图片 URL(24h 有效)。先试同步;若返回 task_id 再轮询。"""
    body = _body(prompt, model, size)
    if user_id:
        body["user"] = user_id  # 透传给网关做 end-user 归账(若网关侧识别)

    # —— 先按同步试 ——
    r = requests.post(f"{PASS}{GEN_PATH}", headers=_headers(virtual_key), json=body, timeout=poll_timeout)
    r.raise_for_status()
    data = r.json()

    url = _extract_image(data)
    if url:
        return url

    # —— 异步:拿 task_id 后轮询 ——
    task_id = (data.get("output") or {}).get("task_id")
    if not task_id:
        raise RuntimeError(f"既无图片也无 task_id,响应需排查:{data}")

    deadline = poll_timeout
    while deadline > 0:
        time.sleep(2)
        deadline -= 2
        pr = requests.get(f"{PASS}/api/v1/tasks/{task_id}", headers=_headers(virtual_key), timeout=30)
        pr.raise_for_status()
        out = pr.json().get("output") or {}
        status = out.get("task_status")
        if status == "SUCCEEDED":
            results = out.get("results") or []
            if results and results[0].get("url"):
                return results[0]["url"]
            raise RuntimeError(f"任务成功但取不到 url:{out}")
        if status in ("FAILED", "CANCELED"):
            raise RuntimeError(f"任务失败:{out}")
    raise TimeoutError("轮询超时")


if __name__ == "__main__":
    import sys
    key = sys.argv[1] if len(sys.argv) > 1 else "sk-你的网关虚拟key"
    print(generate_image("一只戴墨镜的柴犬,扁平插画风", key, user_id="u_demo"))
