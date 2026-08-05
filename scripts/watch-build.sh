#!/usr/bin/env bash
# codex-build 실행 중 진행 상황을 이벤트 스트림으로 흘려보낸다.
#
# Claude Code의 Monitor 도구에 물려 쓴다. stdout 한 줄이 알림 하나가 되므로
# 의미 있는 변화가 있을 때만 출력한다:
#   - 진행: 새 명령을 실행했을 때 (최소 간격 이상 지났을 때만)
#   - 오류: 거부/실패/예외 라인이 나왔을 때 (즉시)
#   - 정체: 로그가 일정 시간 멈췄을 때 (한 번만)
#   - 종료: STATUS가 done / failed:<code>가 되면 마지막 줄을 내고 종료
#
# 사용: watch-build.sh --run-dir <DIR> [--stall-secs 180] [--poll 10] [--min-interval 45]
set -uo pipefail

RUN_DIR=""
STALL_SECS=180
POLL=10
MIN_INTERVAL=45

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)      RUN_DIR="$2"; shift 2 ;;
    --stall-secs)   STALL_SECS="$2"; shift 2 ;;
    --poll)         POLL="$2"; shift 2 ;;
    --min-interval) MIN_INTERVAL="$2"; shift 2 ;;
    -h|--help)
      echo "사용: watch-build.sh --run-dir <DIR> [--stall-secs 180] [--poll 10] [--min-interval 45]"
      exit 0 ;;
    *) echo "알 수 없는 인자: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$RUN_DIR" ]] || { echo "--run-dir이 필요하다" >&2; exit 2; }

LOG="$RUN_DIR/BUILD.log"
STATUS="$RUN_DIR/STATUS"
START="$(date +%s)"

last_size=0
last_growth="$START"
last_emit=0
stall_warned=0
last_action=""

# 로그 뒷부분에서 codex가 마지막으로 실행한 명령을 뽑아낸다.
# 형식:  exec\n<명령줄>\n in <dir>\n succeeded in Nms:
last_action_line() {
  awk '/^exec$/ { getline nextline; cmd = nextline } END { print cmd }' "$LOG" 2>/dev/null \
    | sed -e 's/^"[^"]*pwsh\.exe" -Command //' \
          -e 's/^"[^"]*bash[^"]*" -lc //' \
          -e "s/^'//" -e "s/'$//" \
          -e 's/[[:space:]]\+/ /g' \
    | cut -c1-110
}

elapsed_str() {
  local e=$(( $(date +%s) - START ))
  printf '%dm%02ds' $((e / 60)) $((e % 60))
}

while true; do
  # ---- 종료 조건 먼저 확인 ----
  st="$(cat "$STATUS" 2>/dev/null | tr -d '\r\n')"
  if [[ "$st" == "done" ]]; then
    n=0
    [[ -f "$RUN_DIR/CHANGED.txt" ]] && n="$(grep -cve '^[[:space:]]*$' "$RUN_DIR/CHANGED.txt" 2>/dev/null || echo 0)"
    echo "[완료] $(elapsed_str) 만에 구현 종료 — 변경 파일 ${n}개. 검수 단계로."
    exit 0
  fi
  if [[ "$st" == failed:* ]]; then
    echo "[실패] $(elapsed_str) — codex ${st}. BUILD.log 끝부분 확인 필요."
    exit 1
  fi

  now="$(date +%s)"
  size=0
  [[ -f "$LOG" ]] && size="$(wc -c < "$LOG" 2>/dev/null || echo 0)"

  if [[ "$size" -gt "$last_size" ]]; then
    # ---- 새로 쌓인 구간에서 오류 신호부터 즉시 보고 ----
    new_chunk="$(tail -c "+$((last_size + 1))" "$LOG" 2>/dev/null)"
    bad="$(printf '%s\n' "$new_chunk" \
            | grep -E 'rejected: |blocked by policy| ERROR |error: |Traceback|failed in [0-9]+ms|stream error|401 |429 |Unauthorized' \
            | head -3)"
    if [[ -n "$bad" ]]; then
      while IFS= read -r line; do
        [[ -n "$line" ]] && echo "[오류] $(elapsed_str) | $(echo "$line" | cut -c1-160)"
      done <<< "$bad"
      last_emit="$now"
    fi

    # ---- 진행 보고는 명령이 바뀌었고 최소 간격이 지났을 때만 ----
    action="$(last_action_line)"
    if [[ -n "$action" && "$action" != "$last_action" && $(( now - last_emit )) -ge $MIN_INTERVAL ]]; then
      echo "[진행] $(elapsed_str) | $action"
      last_action="$action"
      last_emit="$now"
    fi

    last_size="$size"
    last_growth="$now"
    stall_warned=0
  else
    # ---- 로그가 멈췄으면 한 번만 경고 ----
    if [[ $stall_warned -eq 0 && $(( now - last_growth )) -ge $STALL_SECS ]]; then
      echo "[정체] $(elapsed_str) | 로그가 $(( now - last_growth ))초째 변화 없음. 마지막 동작: ${last_action:-(없음)}"
      stall_warned=1
    fi
  fi

  sleep "$POLL"
done
