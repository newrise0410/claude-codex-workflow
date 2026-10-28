#!/usr/bin/env bash
# 지금 codex에서 쓸 수 있는 구현 모델 목록을 뽑는다.
#
# 모델 라인업은 수시로 바뀌므로 워크플로우는 모델명을 박아두지 않는다.
# `codex debug models`의 카탈로그(수백 KB JSON)를 사람이 고를 수 있는 몇 줄로 줄이고,
# 사용자 codex 설정(config.toml)의 기본 모델·effort를 함께 보여준다.
#
# 사용: list-models.sh
set -uo pipefail

case "${1:-}" in
  -h|--help) echo "사용: list-models.sh"; exit 0 ;;
  "") ;;
  *) echo "알 수 없는 인자: $1" >&2; exit 2 ;;
esac

command -v codex >/dev/null 2>&1 || {
  echo "[list-models] codex CLI를 찾을 수 없다. https://developers.openai.com/codex/cli 에서 설치하고 'codex login'을 마쳐라." >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  echo "[list-models] python3가 필요하다. 없으면 'codex' 실행 후 /model 에서 직접 확인해라." >&2
  exit 1
}

CATALOG="$(codex debug models 2>/dev/null)" || {
  echo "[list-models] 'codex debug models' 실패. 'codex login' 상태를 확인해라." >&2
  exit 1
}

CONFIG="${CODEX_HOME:-$HOME/.codex}/config.toml"

PY_SRC="$(cat <<'PY'
import json, re, sys

config_path = sys.argv[1]
text = sys.stdin.read()
try:
    models = json.loads(text[text.index("{"):])["models"]
except (ValueError, KeyError):
    sys.exit("[list-models] 모델 카탈로그를 해석하지 못했다.")

# config.toml 최상위의 model / model_reasoning_effort만 본다. 프로필은 무시한다.
default = {}
try:
    with open(config_path, encoding="utf-8") as f:
        for line in f:
            if line.lstrip().startswith("["):
                break
            m = re.match(r'\s*(model|model_reasoning_effort)\s*=\s*"([^"]*)"', line)
            if m:
                default[m.group(1)] = m.group(2)
except OSError:
    pass

d_model = default.get("model", "(codex 내장 기본값)")
d_effort = default.get("model_reasoning_effort", "(모델 기본값)")
print(f"기본값: model={d_model} effort={d_effort}  ({config_path})")
print()

rows = [m for m in models if m.get("visibility") == "list"]
rows.sort(key=lambda m: m.get("priority", 999))
width = max((len(m["slug"]) for m in rows), default=10) + 2
for m in rows:
    mark = "*" if m["slug"] == default.get("model") else " "
    efforts = "|".join(e["effort"] for e in m.get("supported_reasoning_levels", []))
    print(f"{mark} {m['slug']:<{width}}{efforts:<34}{m.get('description', '')}")
PY
)"

printf '%s' "$CATALOG" | python3 -I -c "$PY_SRC" "$CONFIG"
