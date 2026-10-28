# claude-codex-workflow

기획은 **Claude**(기본 Fable), 구현은 **Codex**, 검수는 다시 **Claude**에게 맡기는 Claude Code 워크플로우.

각 모델을 잘하는 자리에 놓는다. Claude는 요구를 읽고 저장소를 파악해 구조를 짜는 데 강하고, Codex는 확정된 사양을 코드로 옮기는 일을 싸게 처리한다. 두 모델 사이를 잇는 계약이 `PLAN.md`다.

모델은 박아두지 않는다. 시작할 때 **Claude(기획·검수)와 Codex(구현)의 모델과 effort를 사용자가 고른다.** Claude 쪽 선택지는 Claude Code의 서브에이전트가 받는 모델·effort이고, Codex 쪽은 `codex debug models`로 읽은 지금의 카탈로그다. codex 라인업은 몇 달마다 바뀌기 때문이다. 기본값은 Claude가 `fable`, Codex가 사용자 codex 설정(`~/.codex/config.toml`)이다.

```
사용자 요청
    │
    ▼
[0] 모델 선택 · 사용자 ─────────────► MODELS.txt
    │  Claude 모델/effort, Codex 모델/effort
    │
    ▼
[1] 기획 · Claude ────────────────► PLAN.md
    │  저장소 조사, 파일별 작업, 인터페이스 계약, 검증 명령
    │
    ▼
[2] 구현 · Codex ─────────────────► DIFF.patch + BUILD_SUMMARY.md
    │  카탈로그에서 고른 모델 / effort / workspace-write
    │
    ▼
[3] 검수 · Claude ────────────────► REVIEW.md
       계획 대비 이행 확인, 검증 명령 실행, PASS/FAIL 판정
```

검수는 1회다. 자동 재작업 루프는 없다 — FAIL이면 사람이 보고 판단한다.

## 설계 의도

구현 모델이 저장소를 뒤지느라 토큰을 쓰면 가성비가 사라진다. **탐색은 기획 단계에서 끝내고 구현 단계는 코드만 쓰게 만드는 것**이 핵심이다. 그래서 `PLAN.md`에는 "인증 모듈 어딘가"가 아니라 `src/auth/session.ts:42의 createSession(userId: string): Promise<Session>`이 들어간다.

계획서가 부실하면 이 워크플로우는 그냥 비싼 우회로가 된다.

## 요구사항

- [Claude Code](https://claude.com/claude-code)
- [Codex CLI](https://developers.openai.com/codex/cli) — 설치 후 `codex login`
- 모델 목록 정리에 `python3` (macOS/Linux). Windows는 PowerShell만 있으면 된다
- git 저장소 (검수 단계가 diff를 읽는다)

## 설치

```
/plugin marketplace add newrise0410/claude-codex-workflow
/plugin install claude-codex@claude-codex-workflow
```

업데이트는 `/plugin marketplace update claude-codex-workflow`.

플러그인을 쓰지 않고 특정 프로젝트에만 넣으려면 `agents/`와 `skills/`를 그 프로젝트의 `.claude/` 아래로 복사하면 된다. 그 경우 스킬 이름에 `claude-codex:` 접두사가 붙지 않는다.

## 사용

```
/claude-codex:plan-and-build 로그인 폼에 이메일 검증 추가하고 실패 케이스 테스트도 같이
```

또는 그냥 자연어로 — "이거 fable로 기획해서 codex한테 넘겨줘" 같은 말에도 스킬이 걸린다.

진행 중 사용자가 개입하는 지점은 세 곳뿐이다.

1. 시작할 때 Claude·Codex 모델과 effort를 고른다(질문 하나에 네 항목). 요청에 이미 적은 항목은("기획은 opus, 구현은 gpt-6-luna max") 묻지 않는다.
2. 계획서에 미해결 질문이 있으면 답한다.
3. 검수 결과를 보고 머지할지, 고칠지, 버릴지 정한다.

## 산출물

실행마다 `.pnb/runs/<NNN>-<슬러그>/`에 남는다.

| 파일 | 내용 |
|---|---|
| `PLAN.md` | Fable이 쓴 사양서. 구현자가 읽는 유일한 계약 |
| `MODELS.txt` | 사용자가 고른 Claude·Codex 모델과 effort. 재검수·수정 라운드에서 그대로 쓴다 |
| `BUILD_PROMPT.md` | codex에게 넘긴 지시문 |
| `BUILD.log` | codex 전체 출력 |
| `BUILD_SUMMARY.md` | codex의 구현 보고 (마지막 메시지) |
| `BUILD_MODEL.txt` | 실제로 쓴 모델과 effort. `--resume` 때 그대로 이어받는다 |
| `DIFF.patch` | 구현 전후 diff. 신규 파일 포함, `.pnb` 제외 |
| `CHANGED.txt` | 변경 파일 목록 |
| `REVIEW.md` | Fable의 검수 결과와 판정 |
| `STATUS` | `running` / `done` / `failed:<code>` |
| `BASE_HEAD.txt` | 구현 시작 시점의 커밋 SHA |
| `BASE_UNTRACKED.txt` | 구현 시작 시점에 이미 있던 untracked 파일 + 내용 해시 |

`BASE_UNTRACKED.txt`가 있는 이유: 저장소에 커밋 안 된 파일이 있는 상태로 구현을 돌리면, 그 파일들이 전부 "구현자가 새로 만든 파일"로 diff에 잡혀 검수자가 엉뚱한 범위 이탈을 보고한다. 스크립트가 빌드 전 스냅샷을 떠서 **내용이 그대로인 것만** diff에서 걸러낸다. 구현 도중 내용이 바뀐 파일은 그대로 남으므로 진짜 범위 이탈은 놓치지 않는다.

`.pnb/`는 기본적으로 `.gitignore`에 들어간다. `PLAN.md`와 `REVIEW.md`를 이력으로 남기고 싶으면 빼도 된다.

## 스크립트 직접 실행

지금 쓸 수 있는 모델부터 본다.

```bash
bash scripts/list-models.sh        # Windows: pwsh scripts/list-models.ps1
```

```
기본값: model=gpt-6-astra effort=high  (/home/me/.codex/config.toml)

  gpt-6.1-sol    low|medium|high|xhigh|max|ultra   Latest workhorse model for coding and everyday work.
* gpt-6-astra    low|medium|high|xhigh|max|ultra   Frontier intelligence for the most demanding work.
  gpt-6-luna     low|medium|high|xhigh|max         Fast and affordable model for easier tasks.
  ...
```

`*`가 현재 기본 모델이다. 위 목록은 2026년 10월 기준 예시이고 실제 출력은 계정과 시점에 따라 다르다.

구현 단계만 따로 돌릴 수 있다.

```powershell
pwsh scripts/codex-build.ps1 -RunDir .pnb/runs/001-add-login
```

```bash
bash scripts/codex-build.sh --run-dir .pnb/runs/001-add-login
```

| 옵션 | 기본값 | 설명 |
|---|---|---|
| `-RunDir` / `--run-dir` | (필수) | `PLAN.md`와 `BUILD_PROMPT.md`가 있는 디렉터리 |
| `-RepoRoot` / `--repo-root` | 현재 디렉터리 | codex의 작업 루트 |
| `-Model` / `--model` | codex 설정의 `model` | 구현 모델. `list-models`에 나온 이름 |
| `-Effort` / `--effort` | codex 설정의 `model_reasoning_effort` | `low`\|`medium`\|`high`\|`xhigh`\|`max`\|`ultra` (모델마다 지원 범위가 다르다) |
| `-Sandbox` / `--sandbox` | `workspace-write` | `read-only`\|`workspace-write`\|`danger-full-access` |
| `-PromptFile` / `--prompt-file` | `<RunDir>/BUILD_PROMPT.md` | codex에게 줄 지시문 |
| `-Resume` / `--resume` | off | 직전 codex 세션을 이어서 실행 |

`-Resume`는 검수 지적사항을 반영시킬 때 쓴다. 같은 세션을 이어받아 codex가 자기가 방금 쓴 코드의 맥락을 유지한다. 모델·effort를 따로 주지 않으면 `BUILD_MODEL.txt`에 남은 값을 그대로 쓴다.

## 진행 상황 보기

구현은 몇 분에서 수십 분까지 걸리고, 백그라운드로 던지면 끝날 때 알림 하나뿐이다. 그 사이 뭘 하는지, 뻗었는지 알려면 감시기를 같이 띄운다.

```bash
bash scripts/watch-build.sh --run-dir .pnb/runs/001-add-login
```

의미 있는 변화가 있을 때만 한 줄씩 출력한다 — 로그 전문을 쏟아내지 않는다.

```
[진행] 2m14s | node --test examples/todo/todo.test.js
[오류] 3m02s | rejected: blocked by policy
[정체] 6m30s | 로그가 195초째 변화 없음. 마지막 동작: node examples/todo/check.js
[완료] 8m47s 만에 구현 종료 — 변경 파일 6개. 검수 단계로.
```

| 옵션 | 기본값 | 설명 |
|---|---|---|
| `--stall-secs` | `180` | 로그가 이 시간(초) 이상 안 움직이면 `[정체]` 경고 |
| `--poll` | `10` | 확인 주기(초) |
| `--min-interval` | `45` | `[진행]` 보고 최소 간격(초). 오류·정체·종료는 이 간격을 무시하고 즉시 |

스킬은 이걸 Claude Code의 Monitor 도구에 물려 자동으로 띄운다. `STATUS`가 확정되면 감시기도 스스로 종료한다.

## 비용 조절

계획서가 촘촘할수록 구현 모델은 가벼워도 된다. 그게 이 워크플로우의 전제다.

| 상황 | 조정 |
|---|---|
| 작업이 단순함 | effort를 `medium`이나 `high`로 낮춘다 |
| 계획이 상세하고 기계적인 작업 | 카탈로그에서 가볍다고 설명된 모델 (예: `gpt-6-luna`) + 높은 effort |
| 계획이 복잡하거나 구현자가 헤맴 | 주력·최상위 모델 (예: `gpt-6.1-sol`, `gpt-6-astra`) |
| 기획이 부실함 | Claude 모델이나 effort를 올린다. 가장 효과가 큰 조정이다 |
| 기획·검수도 아껴야 함 | Claude 모델을 가벼운 것(예: `sonnet`)으로 바꾸거나 effort를 낮춘다 |

예시 모델명은 2026년 10월 기준이다. 실제로 고를 때는 `list-models` 출력을 믿어라.

## 이 워크플로우를 쓰지 말아야 할 때

- 한두 줄 수정, 오타, 설정값 변경 — 오케스트레이션 비용이 작업보다 크다
- 요구사항이 아직 흐릿할 때 — 계획서는 대화의 대체물이 아니다
- 탐색적 디버깅 — 계획을 세울 수 있는 상태가 아니다

## 라이선스

MIT
