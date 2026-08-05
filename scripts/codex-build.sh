#!/usr/bin/env bash
# PLAN.md를 codex-luna-max에게 넘겨 구현시키고, 결과 diff를 검수용으로 캡처한다.
# codex-build.ps1의 POSIX 대응판. 사용법은 --help 참고.
set -uo pipefail

RUN_DIR=""
REPO_ROOT="$(pwd)"
MODEL="gpt-5.6-luna"
EFFORT="max"
SANDBOX="workspace-write"
PROMPT_FILE=""
RESUME=0

usage() {
  cat <<'EOF'
사용법: codex-build.sh --run-dir <DIR> [옵션]

  --run-dir <DIR>     실행 산출물 디렉터리. PLAN.md / BUILD_PROMPT.md가 여기 있어야 한다. (필수)
  --repo-root <DIR>   codex가 작업할 저장소 루트 (기본: 현재 디렉터리)
  --model <NAME>      구현 모델 (기본: gpt-5.6-luna)
  --effort <LEVEL>    low|medium|high|xhigh|max (기본: max)
  --sandbox <MODE>    read-only|workspace-write|danger-full-access (기본: workspace-write)
  --prompt-file <F>   지시문 파일 (기본: <RUN_DIR>/BUILD_PROMPT.md)
  --resume            직전 codex 세션을 이어서 실행

남기는 산출물: STATUS, BUILD.log, BUILD_SUMMARY.md, DIFF.patch, CHANGED.txt, BASE_HEAD.txt
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)     RUN_DIR="$2"; shift 2 ;;
    --repo-root)   REPO_ROOT="$2"; shift 2 ;;
    --model)       MODEL="$2"; shift 2 ;;
    --effort)      EFFORT="$2"; shift 2 ;;
    --sandbox)     SANDBOX="$2"; shift 2 ;;
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    --resume)      RESUME=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "알 수 없는 인자: $1" >&2; usage; exit 2 ;;
  esac
done

die() { echo "[codex-build] $*" >&2; exit 1; }

command -v codex >/dev/null 2>&1 || \
  die "codex CLI를 찾을 수 없다. https://developers.openai.com/codex/cli 에서 설치하고 'codex login'을 마쳐라."

[[ -n "$RUN_DIR" ]] || { usage; exit 2; }
[[ -d "$RUN_DIR" ]] || die "RunDir이 없다: $RUN_DIR"

RUN_DIR="$(cd "$RUN_DIR" && pwd)"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

[[ -f "$RUN_DIR/PLAN.md" ]] || die "PLAN.md가 없다: $RUN_DIR/PLAN.md — 기획 단계를 먼저 끝내라."

[[ -n "$PROMPT_FILE" ]] || PROMPT_FILE="$RUN_DIR/BUILD_PROMPT.md"
[[ -f "$PROMPT_FILE" ]] || die "지시문 파일이 없다: $PROMPT_FILE"
PROMPT_FILE="$(cd "$(dirname "$PROMPT_FILE")" && pwd)/$(basename "$PROMPT_FILE")"

STATUS_PATH="$RUN_DIR/STATUS"
LOG_PATH="$RUN_DIR/BUILD.log"
SUMMARY_PATH="$RUN_DIR/BUILD_SUMMARY.md"
DIFF_PATH="$RUN_DIR/DIFF.patch"
CHANGED_PATH="$RUN_DIR/CHANGED.txt"
BASE_HEAD_PATH="$RUN_DIR/BASE_HEAD.txt"
BASE_UNTRACKED_PATH="$RUN_DIR/BASE_UNTRACKED.txt"

IS_GIT=0
if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IS_GIT=1
  if [[ $RESUME -eq 0 ]]; then
    git -C "$REPO_ROOT" rev-parse HEAD > "$BASE_HEAD_PATH" 2>/dev/null || echo "(no commits yet)" > "$BASE_HEAD_PATH"

    # 빌드 전부터 워킹 트리에 있던 untracked 파일을 내용 해시와 함께 기록한다.
    # 이걸 안 하면 커밋 안 된 기존 파일이 전부 "구현자가 새로 만든 파일"로 diff에 잡혀
    # 검수자가 엉뚱한 범위 이탈을 보고하게 된다.
    : > "$BASE_UNTRACKED_PATH"
    (
      cd "$REPO_ROOT"
      git ls-files --others --exclude-standard -- . ':(exclude).pnb' 2>/dev/null | while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        h="$(git hash-object -- "$f" 2>/dev/null)" || continue
        [[ -n "$h" ]] && printf '%s\t%s\n' "$h" "$f" >> "$BASE_UNTRACKED_PATH"
      done
    )
  fi
fi

echo "running" > "$STATUS_PATH"

# 프롬프트 본문은 파일로 넘긴다. 인자에 한글 장문을 실으면 셸 인코딩/길이 문제가 생긴다.
PROMPT="Read the file at $PROMPT_FILE and follow it exactly. It is your complete task brief."

# `codex exec resume`는 -s/-C를 받지 않는다. 그쪽은 -c 설정과 cwd로 대신한다.
if [[ $RESUME -eq 1 ]]; then
  ARGS=(exec resume --last
        -m "$MODEL"
        -c "model_reasoning_effort=$EFFORT"
        -c "sandbox_mode=$SANDBOX"
        -o "$SUMMARY_PATH"
        "$PROMPT")
else
  ARGS=(exec
        -m "$MODEL"
        -c "model_reasoning_effort=$EFFORT"
        -s "$SANDBOX"
        -C "$REPO_ROOT"
        -o "$SUMMARY_PATH"
        "$PROMPT")
fi

echo "[codex-build] model=$MODEL effort=$EFFORT sandbox=$SANDBOX"
echo "[codex-build] repo=$REPO_ROOT"
echo "[codex-build] brief=$PROMPT_FILE"
echo

( cd "$REPO_ROOT" && codex "${ARGS[@]}" 2>&1 ) | tee "$LOG_PATH"
EXIT_CODE="${PIPESTATUS[0]}"

if [[ $IS_GIT -eq 1 ]]; then
  # 실제 인덱스를 건드리지 않도록 임시 인덱스에서 diff를 만든다.
  # 신규 파일도 patch에 포함되고, 워크플로우 산출물(.pnb)은 제외한다.
  TMP_INDEX="$(mktemp -u)"
  (
    export GIT_INDEX_FILE="$TMP_INDEX"
    cd "$REPO_ROOT"
    git read-tree HEAD >/dev/null 2>&1
    git add -A -- . ':(exclude).pnb' >/dev/null 2>&1

    # 빌드 전부터 있던 untracked 파일 중 내용이 그대로인 것은 임시 인덱스에서 뺀다.
    # 내용이 바뀐 것은 남겨둔다 — 그건 구현자가 손댄 진짜 변경이다.
    if [[ -f "$BASE_UNTRACKED_PATH" ]]; then
      while IFS=$'\t' read -r old_hash rel_path; do
        [[ -n "$old_hash" && -n "$rel_path" && -f "$rel_path" ]] || continue
        new_hash="$(git hash-object -- "$rel_path" 2>/dev/null)" || continue
        [[ "$new_hash" == "$old_hash" ]] && git rm --cached --quiet --force -- "$rel_path" >/dev/null 2>&1
      done < "$BASE_UNTRACKED_PATH"
    fi

    git diff --cached HEAD -- . ':(exclude).pnb' > "$DIFF_PATH" 2>/dev/null
    git diff --cached --name-status HEAD -- . ':(exclude).pnb' > "$CHANGED_PATH" 2>/dev/null
  )
  rm -f "$TMP_INDEX"
else
  echo "(git 저장소가 아니라 diff를 캡처하지 못했다)" > "$DIFF_PATH"
  echo "(git 저장소가 아님)" > "$CHANGED_PATH"
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
  echo "done" > "$STATUS_PATH"
  CHANGED_COUNT="$(grep -cve '^[[:space:]]*$' "$CHANGED_PATH" 2>/dev/null || echo 0)"
  echo
  echo "[codex-build] 완료. 변경 파일 ${CHANGED_COUNT}개."
  echo "[codex-build] 산출물: $RUN_DIR"
else
  echo "failed:$EXIT_CODE" > "$STATUS_PATH"
  echo
  echo "[codex-build] 실패 (exit $EXIT_CODE). 로그: $LOG_PATH"
fi

exit "$EXIT_CODE"
