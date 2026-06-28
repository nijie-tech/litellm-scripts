"""应用层选模型逻辑(中文 C 端 agent)起手模块。

设计原则(对标 Cursor/Copilot/Windsurf 的 auto):
- 决策在应用层做——你最清楚「哪个功能入口、对话多深、是不是代码」。
- 三层信号:① 功能入口直选(确定性) ② 中文复杂度分档 ③ 可用性交给网关 fallback。
- 不可变风格:纯函数,不修改入参。
- 选完只产出一个 model_name,调用网关时带上,其余(兜底/归账)由网关处理。
"""
from __future__ import annotations

# ① 功能入口 → 模型(优先级最高,确定性)。app 知道请求来自哪个功能。
FEATURE_MODEL: dict[str, str] = {
    "code":      "kimi-k2.7-code",             # 代码场景:用代码专长模型
    "translate": "deepseek/deepseek-v4-flash",  # 翻译/格式化:便宜快
    "summarize": "deepseek/deepseek-v4-flash",
    "deep":      "qwen3.7-max",                 # 显式「深度/专家模式」
    # "chat" 不在表里 → 落到复杂度判断
}

# ② 通用对话:复杂度档位 → 模型
TIER_MODEL: dict[str, str] = {
    "SIMPLE":    "deepseek/deepseek-v4-flash",
    "MEDIUM":    "qwen3.7-plus",
    "COMPLEX":   "moonshot/kimi-k2.6",
    "REASONING": "qwen3.7-max",
}
_TIER_RANK = {"SIMPLE": 0, "MEDIUM": 1, "COMPLEX": 2, "REASONING": 3}

# 中文关键词表(可持续维护;这才是中文 C 端的关键,网关英文黑盒做不到)
_REASONING_KW = ("证明", "推导", "分析", "权衡", "取舍", "设计", "架构", "方案",
                 "优化", "算法", "复杂度", "论证", "推理", "评估", "比较", "为什么", "原理")
_CODE_KW = ("代码", "函数", "报错", "调试", "重构", "并发", "线程", "接口",
            "```", "def ", "class ", "sql", "api", "异常", "栈")
_MULTISTEP_KW = ("首先", "然后", "其次", "最后", "步骤", "第一", "第二", "分别", "列出")


def score_complexity(text: str) -> float:
    """对一段中文文本打 0~1 复杂度分。纯规则、零外部调用、亚毫秒。"""
    length_score = min(len(text) / 600.0, 1.0)            # 长度(中文按字符)
    reason = min(sum(k in text for k in _REASONING_KW) / 3.0, 1.0)
    code = min(sum(k in text.lower() for k in _CODE_KW) / 2.0, 1.0)
    steps = min(sum(k in text for k in _MULTISTEP_KW) / 3.0, 1.0)
    return 0.20 * length_score + 0.35 * reason + 0.25 * code + 0.20 * steps


def pick_tier(score: float) -> str:
    """分数 → 档位。阈值可按真实流量分布调。"""
    if score >= 0.38:
        return "REASONING"
    if score >= 0.20:
        return "COMPLEX"
    if score >= 0.08:
        return "MEDIUM"
    return "SIMPLE"


def select_model(feature: str, text: str, session_model: str | None = None) -> str:
    """产出最终 model_name。
    feature: 功能入口标识(如 'code'/'translate'/'chat')。
    text: 用户本轮输入。
    session_model: 本会话此前用过的模型——用于「不中途降档」(对齐主流:稳定>聪明,省缓存)。
    """
    if feature in FEATURE_MODEL:
        return FEATURE_MODEL[feature]

    chosen = TIER_MODEL[pick_tier(score_complexity(text))]

    # 会话内只升不降:已经用强模型了就别中途换回弱的(避免破坏上下文/缓存)
    if session_model and _rank(session_model) > _rank(chosen):
        return session_model
    return chosen


def explain(feature: str, text: str, session_model: str | None = None) -> dict:
    """返回一条可记日志的决策记录——灰度/观测阶段用:只记录不改行为,看分档分布是否合理。"""
    score = score_complexity(text)
    return {
        "feature": feature,
        "via": "feature" if feature in FEATURE_MODEL else "complexity",
        "score": round(score, 3),
        "tier": pick_tier(score),
        "model": select_model(feature, text, session_model),
        "input_len": len(text),
    }


def _rank(model: str) -> int:
    """模型在档位阶梯上的强弱序;不在表里的(如 code 专长)给最高,避免被降档。"""
    for tier, m in TIER_MODEL.items():
        if m == model:
            return _TIER_RANK[tier]
    return max(_TIER_RANK.values())


# ───────────────────────── 调用网关示例 ─────────────────────────
def build_request(feature: str, text: str, user_id: str,
                  session_model: str | None = None) -> dict:
    """组装发给 LiteLLM 网关的请求体。注意:必须带 user 用于归账/限额。"""
    return {
        "model": select_model(feature, text, session_model),
        "user": user_id,                       # ← 终端用户归账,别漏
        "messages": [{"role": "user", "content": text}],
        # "stream": True,                      # C 端体验建议开流式
    }


if __name__ == "__main__":
    # 冒烟:验证中文也能正确分档(网关英文黑盒做不到的)
    cases = [
        ("chat", "你好呀"),
        ("chat", "翻译成英文:今天天气不错"),
        ("chat", "用三句话解释什么是HTTP缓存"),
        ("chat", "设计一个支持千万级用户的短链系统,分析分库分表、缓存穿透、ID生成的取舍"),
        ("chat", "证明1到n的立方和等于求和的平方,给出归纳法完整推导并分析每一步"),
        ("code", "帮我写个线程安全的LRU缓存"),
        ("translate", "把这段翻译成日语"),
    ]
    for feat, q in cases:
        m = select_model(feat, q)
        s = score_complexity(q)
        print(f"[{feat:9}] score={s:.2f}  → {m}    « {q[:24]}")
