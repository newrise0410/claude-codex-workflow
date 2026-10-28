---
name: plan-and-build
description: 기획은 Claude, 구현은 Codex, 검수는 다시 Claude에게 맡기는 2-모델 워크플로우. 양쪽 모델과 effort는 실행할 때 사용자가 고른다(Codex는 현재 카탈로그에서). 사용자가 "/plan-and-build", "기획하고 구현해줘", "fable로 기획해서 codex로 짜줘", "plan and build", "코덱스한테 넘겨줘"라고 하거나 기능 개발을 모델 분업으로 돌리고 싶어할 때 사용한다.
metadata:
  short-description: Claude 기획 → Codex 구현 → Claude 검수 (모델·effort 선택)
---

# plan-and-build

기획·구현·검수를 서로 다른 모델에 나눠 맡긴다. 너(오케스트레이터)는 코드를 직접 쓰지 않고 단계를 진행시키고 결과를 사람에게 보고한다.

| 단계 | 담당 | 실행 방식 | 산출물 |
|---|---|---|---|
| 0. 모델 선택 | 사용자 | AskUserQuestion | `MODELS.txt` |
| 1. 기획 | Claude (기본 Fable) | `fable-planner` 서브에이전트 | `PLAN.md` |
| 2. 구현 | Codex (사용자가 고른 모델) | `codex-build` 스크립트 | `BUILD_SUMMARY.md`, `DIFF.patch` |
| 3. 검수 | Claude (기본 Fable) | `fable-reviewer` 서브에이전트 | `REVIEW.md` |

검수는 **1회**다. 자동 재작업 루프는 돌리지 않는다. FAIL이 나오면 사람에게 보고하고, 수정 반영은 사용자가 요청할 때만 한다(아래 "지적사항 반영" 참고).

## 이 워크플로우의 전제

구현 모델이 저장소를 뒤지느라 토큰을 쓰면 가성비가 사라진다. **탐색은 기획 단계에서 끝내고, 구현 단계는 코드만 쓰게 만드는 것**이 설계 의도다. `PLAN.md`가 부실하면 이 워크플로우는 그냥 비싼 우회로가 된다. 계획서 품질에 가장 신경 써라.

## 언제 쓰지 말아야 하나

먼저 판단하고, 아니면 그냥 직접 해라. 사용자가 명시적으로 이 워크플로우를 지정했으면 그대로 따른다.

- 한두 줄 수정, 오타, 설정값 변경 → 3단계 오케스트레이션 비용이 작업보다 크다.
- 요구사항 자체가 아직 흐릿함 → 먼저 사용자와 정리해라. 계획서는 대화의 대체물이 아니다.
- 탐색적 디버깅("왜 이게 안 되지") → 계획을 세울 수 있는 상태가 아니다. 원인부터 찾아라.

## 절차

### 0. 준비

`codex` CLI와 로그인 상태를 확인한다. 없으면 바로 알리고 멈춰라.

```bash
codex --version
```

작업 슬러그를 정하고 실행 디렉터리를 만든다. `NNN`은 `.pnb/runs/` 아래 기존 항목 다음 번호(3자리, 001부터).

```
.pnb/runs/<NNN>-<영문-슬러그>/
```

`.pnb/`가 `.gitignore`에 없고 저장소가 git이면, 산출물을 커밋할지 사용자에게 한 번 묻고 원치 않으면 `.gitignore`에 `.pnb/`를 추가해라. 묻지 않고 임의로 `.gitignore`를 고치지 마라.

#### 0-1. 모델과 effort 고르기

기획·검수(Claude)와 구현(Codex) 모두 **모델과 effort를 사용자가 고른다.** 결과 품질과 비용을 가장 크게 가르는 선택이라 기본값을 몰래 쓰지 마라. 기획에 들어가기 전에 한 번만 묻는다.

선택지는 기억으로 지어내지 말고 지금 쓸 수 있는 것에서 가져온다.

- **Claude**: 네 Agent 도구의 `model` 파라미터가 받는 값과 `effort` 파라미터가 받는 값이 선택지다. 기본 모델은 에이전트 정의의 `model: fable`이고, 기본 effort는 파라미터를 생략했을 때(에이전트의 평소 effort)다.
- **Codex**: 카탈로그를 읽는다. 라인업이 수시로 바뀌므로 매번 돌려라.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/list-models.sh"
  ```

  Windows는 `pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/scripts/list-models.ps1"`. 첫 줄은 사용자 codex 설정(`config.toml`)의 기본 모델·effort이고, 이어서 `모델  지원 effort  설명`이 한 줄씩 나온다. `*`가 현재 기본 모델이다.

AskUserQuestion **한 번에 네 질문**으로 묻는다.

| 질문 | 첫 선택지 (라벨에 `(기본값)`) | 나머지 선택지 |
|---|---|---|
| Claude 모델 (기획·검수) | `fable` | Agent 도구가 받는 다른 모델들 |
| Claude effort | 생략 = 에이전트 평소 effort | Agent 도구의 `effort` 값 중 2~3개 |
| Codex 모델 (구현) | `*` 표시 모델 | 목록 위쪽 순서대로, 최대 4개 |
| Codex effort | config의 기본 effort | 목록의 모든 모델이 지원하는 값 중 2~3개 |

- Codex 선택지의 description에는 카탈로그 설명을 그대로 옮긴다. 이름만 보고 성격을 지어내지 마라.
- 판단을 도울 한 줄은 붙여도 된다. 이 워크플로우의 전제는 **계획이 촘촘하면 구현 모델은 가벼워도 된다**는 것이다. 무게는 기획 쪽에 두는 편이 맞다. 다만 고르는 건 사용자다.
- 사용자가 요청에서 이미 정한 항목은 묻지 않는다("기획은 opus, 구현은 gpt-6-luna max"). 넷 다 정했으면 질문 자체를 건너뛴다.
- 고른 Codex 모델이 지원하지 않는 effort가 들어왔거나 목록에 없는 모델명이면 알리고 그 항목만 다시 묻는다.
- 기획과 검수를 다른 모델로 하고 싶다는 답(Other)이 오면 따로 기록해 각 단계에 쓴다.

고른 값을 `<RUN_DIR>/MODELS.txt`에 남긴다. 재검수나 수정 반영 라운드에서 같은 값을 쓰기 위해서다. Codex 쪽은 스크립트가 실제로 쓴 값을 `BUILD_MODEL.txt`에 따로 남긴다.

```
claude_model=fable
claude_effort=
codex_model=gpt-6-luna
codex_effort=max
```

빈 값은 기본값이라는 뜻이다. Agent 호출에서 `effort`를 생략하고, 스크립트에서 플래그를 생략한다.

### 1. 기획 — Claude

`fable-planner` 서브에이전트를 띄운다. 플러그인으로 설치했으면 `claude-codex:fable-planner`, 저장소에 직접 복사했으면 `fable-planner`다. Agent 호출 시 0-1에서 고른 `model`을 명시하고, effort를 골랐으면 `effort`도 넘긴다. 사용자가 직접 고른 값이므로 넘겨도 된다. 기본값을 골랐으면 `effort`는 생략한다.

프롬프트에 반드시 넣을 것:

- 사용자의 원래 요청 **원문 그대로**. 요약해서 넘기지 마라 — 요약 과정에서 요구가 소실된다.
- 이번 대화에서 사용자가 추가로 말한 제약(쓰지 말 라이브러리, 기한, 스타일 등).
- `PLAN.md`를 쓸 절대 경로: `<RUN_DIR>/PLAN.md`
- 저장소 루트 절대 경로.

에이전트가 돌아오면 반환값에서 `OPEN_QUESTIONS`를 본다.

- `0` → 2단계로 진행. 진행 전에 사용자에게 계획 요약(제목, 건드릴 파일 수, 2~3문장 요약)과 `PLAN.md` 경로를 한 번 보여준다.
- `1` 이상 → **멈춘다.** `PLAN.md`의 `## 8. 확인 필요`를 읽고 AskUserQuestion으로 물어라. 답을 받으면 그 답을 프롬프트에 얹어 `fable-planner`를 다시 호출해 계획을 갱신시킨다(같은 경로에 덮어쓰기). 구현자에게 미해결 질문이 담긴 계획을 넘기지 마라.

### 2. 구현 — Codex

#### 2-1. 실행

0-1에서 고른 Codex 모델·effort를 쓴다. 먼저 `<RUN_DIR>/BUILD_PROMPT.md`를 만든다. 템플릿은 `references/build-prompt.md`에 있다. `<PLAN_PATH>` 자리에 `PLAN.md`의 절대 경로를 넣고, 그 외에는 문구를 바꾸지 마라.

그다음 스크립트를 **백그라운드로** 실행한다. 구현은 10분을 넘길 수 있어서 포그라운드 타임아웃에 걸린다. 백그라운드로 돌리면 종료 시 알림이 온다.

Windows — PowerShell 도구, `run_in_background: true`:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/codex-build.ps1" -RunDir "<RUN_DIR>" -RepoRoot "<REPO_ROOT>" -Model "<MODEL>" -Effort "<EFFORT>"
```

macOS / Linux — Bash 도구, `run_in_background: true`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-build.sh" --run-dir "<RUN_DIR>" --repo-root "<REPO_ROOT>" --model "<MODEL>" --effort "<EFFORT>"
```

플러그인이 아니라 저장소에 직접 둔 경우 `${CLAUDE_PLUGIN_ROOT}` 대신 실제 경로를 쓴다.

#### 2-2. 진행 감시기를 반드시 같이 띄운다

백그라운드 실행은 끝날 때 알림 하나만 준다. 그것만으로는 구현이 몇 분째 뭘 하고 있는지, 중간에 뻗었는지 알 수 없다. 빌드를 백그라운드로 던진 **직후** Monitor 도구로 감시기를 걸어라. 이건 선택이 아니다.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/watch-build.sh" --run-dir "<RUN_DIR>"
```

Monitor 호출 시 `description`은 `"codex 구현 진행 (<슬러그>)"`, `timeout_ms`는 예상 소요의 2배(기본 `1800000` = 30분)로 잡아라. 감시기는 다음만 이벤트로 낸다:

| 이벤트 | 의미 | 네가 할 일 |
|---|---|---|
| `[진행]` | codex가 새 명령을 실행 중 (최소 45초 간격) | 그대로 두고 지켜본다 |
| `[오류]` | 샌드박스 거부, 인증 실패, 스택 트레이스 등 | 사용자에게 즉시 알린다. 인증·권한 문제면 빌드를 죽이고 원인부터 해결한다 |
| `[정체]` | 로그가 3분 넘게 안 움직임 | 사용자에게 알린다. 한 번 더 정체되면 `BUILD.log` 끝을 읽고 죽일지 물어라 |
| `[완료]` / `[실패]` | STATUS가 확정됨. 감시기 자동 종료 | 3단계로 가거나 실패를 진단한다 |

`[정체]`가 곧 실패는 아니다 — 리즈닝이 길거나 큰 파일을 쓰는 중일 수 있다. 다만 **두 번 연속 정체되면 사용자에게 판단을 넘겨라.** 말없이 30분을 기다리지 마라.

기본값은 `--stall-secs 180 --min-interval 45`다. 짧은 작업이면 `--stall-secs 90`으로 줄여라.

실행을 걸어놓고 사용자에게 "구현 시작 — 모델 <MODEL> / <EFFORT>, 진행 상황은 감시기가 알려준다"라고 알린 뒤 기다린다. **완료 알림이 오기 전에 결과를 추측해서 보고하지 마라.** 감시기의 `[진행]` 이벤트는 결과가 아니라 살아있다는 신호일 뿐이다.

기본값은 `-Sandbox workspace-write`다. 계획이 저장소 밖 경로를 건드려야 하거나 네트워크 설치가 필요하면 사용자에게 확인받고 `-Sandbox danger-full-access`로 올려라.

완료되면 `<RUN_DIR>/STATUS`를 확인한다.

- `done` → 3단계로.
- `failed:<code>` → `BUILD.log` 끝부분을 읽고 원인을 진단해 사용자에게 보고한다. 흔한 원인: 로그인 만료(`codex login`), 모델 접근 권한 없음 또는 사라진 모델명(`list-models`로 다시 확인), 고른 모델이 지원하지 않는 effort, 샌드박스 거부. 검수 단계는 건너뛴다.

### 3. 검수 — Claude

`fable-reviewer` 서브에이전트를 띄운다. 모델·effort는 1단계와 같은 방식으로 `MODELS.txt`의 값을 쓴다.

프롬프트에 넣을 것 — 전부 **절대 경로**로:

- `PLAN.md`, `DIFF.patch`, `CHANGED.txt`, `BUILD_SUMMARY.md` 경로
- `REVIEW.md`를 쓸 경로: `<RUN_DIR>/REVIEW.md`
- 저장소 루트 (검증 명령을 여기서 돌린다)

검수자에게 **파일 내용을 붙여넣지 마라.** 경로만 주고 직접 읽게 해라. diff를 컨텍스트에 실어 나르면 오케스트레이터 토큰만 태운다.

### 4. 보고

사용자에게 이렇게 알린다:

- **판정** — PASS / PASS_WITH_NITS / FAIL과 한 문장 근거
- **모델** — 기획·검수는 `MODELS.txt`의 Claude 모델·effort, 구현은 `BUILD_MODEL.txt`의 모델·effort
- **변경 규모** — 파일 수, 추가/삭제 줄 수
- **검증 결과** — 통과/전체, 실패한 명령이 있으면 그것
- **BLOCKER·MAJOR 지적사항** — 있으면 요약. MINOR는 개수만.
- **산출물 경로** — `<RUN_DIR>`

판정과 무관하게 코드는 아직 워킹 트리에 있고 커밋되지 않은 상태다. 사용자가 요청하지 않는 한 커밋하지 마라.

## 지적사항 반영 (사용자 요청 시에만)

검수가 FAIL이나 MAJOR를 냈고 사용자가 수정을 원하면:

1. `<RUN_DIR>/FIX_PROMPT.md`를 만든다. `REVIEW.md`의 BLOCKER·MAJOR 항목을 그대로 옮기고, "이 항목들만 고쳐라. 그 외 리팩터링 금지. 다 고친 뒤 PLAN.md `## 5. 검증`을 다시 돌려라." 를 덧붙인다.
2. `-Resume` (bash는 `--resume`) 과 `-PromptFile <RUN_DIR>/FIX_PROMPT.md`로 스크립트를 다시 돌린다. 같은 codex 세션을 이어받아 맥락을 유지한다. 모델·effort를 안 넘기면 `BUILD_MODEL.txt`의 값을 그대로 쓴다. 사용자가 이번엔 다른 모델을 원할 때만 넘겨라.
3. 재검수가 필요하면 3단계를 다시 실행한다. **자동으로 반복하지 마라** — 매 라운드 사용자 요청이 있어야 한다.

## 모델 바꾸기

모델은 0-1에서 사용자가 고른다. 아래는 결과가 마음에 안 들 때 다음 라운드에서 바꾸는 방향이다. Codex 모델명은 `list-models`가 보여주는 것만 믿어라. 이 문서에 예시로 적힌 모델명도 언젠가 낡는다.

| 상황 | 조정 |
|---|---|
| 더 싸게/빠르게 | `-Effort` 낮추기(`high` → `medium`), 또는 카탈로그에서 가볍다고 설명된 모델 |
| 구현자가 헤맨다 | 카탈로그 위쪽의 주력·최상위 모델로 바꾸거나 effort를 올린다 |
| 아무것도 안 넘김 | 사용자 codex `config.toml`의 `model` / `model_reasoning_effort` |
| 기획이 부실하다 | Claude 모델이나 effort를 올린다. 이 워크플로우에서 가장 효과가 큰 조정이다 |
| 기획·검수도 아껴야 한다 | Claude 모델을 한 단계 가벼운 것으로, 또는 effort를 낮춘다 |

## 실패 모드 체크리스트

진행 중 다음이 보이면 멈추고 사용자에게 말해라.

- 계획서에 파일 경로가 없고 "적절한 위치에" 같은 표현이 있다 → 계획을 다시 세워라. 구현자가 헤맨다.
- `DIFF.patch`가 비어 있는데 `STATUS`가 `done`이다 → codex가 아무것도 안 했다. `BUILD.log`를 읽어라.
- `DIFF.patch`에 계획에 없는 파일이 대량으로 있다 → 먼저 `BASE_UNTRACKED.txt`와 대조해라. 거기 있는 경로면 빌드 전부터 커밋 안 된 채 있던 파일이고 구현자 책임이 아니다(스크립트가 자동으로 걸러내지만, 빌드 도중 내용이 바뀐 파일은 남는다). 거기 없는 파일이면 진짜 범위 이탈이니 검수 결과를 그대로 전달하고 되돌릴지 물어라.
- 검수자가 검증 명령을 "돌릴 수 없었다"고 적었다 → 판정을 PASS로 취급하지 마라. 사용자에게 직접 확인이 필요하다고 알려라.
