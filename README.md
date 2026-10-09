# harness-kit

여러 프로젝트에서 재사용하는 개인용 개발 하네스입니다. 공통 작업 규칙은 이 저장소에 한 번만 두고, 새 프로젝트마다 **프로필 + `harness.toml` + 프로젝트 문서**만 생성합니다.

## 빠른 시작

새 프로젝트 폴더를 만들면서 `next-web` 프로필을 적용합니다.

```bash
sh init.sh init ../escape-log \
  --name escape-log \
  --profile next-web \
  --description "친구와 방탈출 기록을 공유하는 서비스"
```

명령은 다음 파일을 대상 프로젝트에 생성합니다.

```text
escape-log/
├── AGENTS.md                 # AI 에이전트가 따라야 할 프로젝트 규칙
├── harness.toml              # 선택한 프로필과 프로젝트별 설정
├── .harness/                 # 공통 워크플로우와 Phase·Step 템플릿
├── docs/
│   ├── INTENT.md             # 왜 만드는지와 범위
│   ├── LLM_WIKI.md           # 구현으로 확인된 사실
│   ├── PRD.md                # 무엇을 만드는지
│   ├── ARCHITECTURE.md       # 어떻게 구성하는지
│   └── ADR/0000-template.md  # 중요한 결정 기록 (선택)
├── phases/                   # 승인된 설계와 Step·evidence 기록
└── scripts/
    ├── harness.sh            # Phase·Step 상태 관리
    └── verify-harness.sh     # 생성 결과 점검
```

생성 뒤에는 `docs/INTENT.md`부터 채우고, 구현을 시작하기 전 `AGENTS.md`와 `harness.toml`을 검토하면 됩니다.

## 문서와 기록의 경계

- `docs/INTENT.md`: 이 프로젝트가 해결할 문제, 성공 조건, 하지 않을 일을 짧게 고정합니다.
- `docs/LLM_WIKI.md`: 구현으로 확인된 구조·명령·계약·운영 사실을 에이전트가 빠르게 읽을 수 있게 요약합니다. 추측이나 계획은 기록하지 않습니다.
- `phases/<phase>/step-<id>-evidence.md`: 한 Step이 어떤 설계·요구사항에서 나왔고 무엇으로 검증됐는지 남깁니다.

## Phase와 Step 워크플로우

Step은 아래 상태 전이만 허용합니다.

```text
planned → in-progress → review_required → completed
                         │
                         └→ planned  (리뷰 수정 요청)
```

Phase 설계가 명시적으로 승인된 뒤에만 Step을 만들 수 있습니다. `phase.md`의 최초 상태는 `approved`, 새 Step의 최초 상태는 `planned`입니다.

```bash
# `--approved`는 설계 승인을 명시적으로 확인한다.
sh scripts/harness.sh phase create authentication "로그인과 인증" --approved

# Step과 그 근거·검증 문서를 함께 만든다.
sh scripts/harness.sh step create authentication 001 "도메인 모델 추가"
sh scripts/harness.sh step create authentication 002 "로그인 API 추가" \
  --depends-on 001

# `harness:next` 워크플로우: planned 상태이면서 선행 Step이 모두 completed인 작업만 보여 준다.
sh scripts/harness.sh next

sh scripts/harness.sh step start authentication 001
sh scripts/harness.sh step review authentication 001
sh scripts/harness.sh step replan authentication 001  # 수정 요청 시
sh scripts/harness.sh step start authentication 001
sh scripts/harness.sh step review authentication 001
sh scripts/harness.sh step complete authentication 001
```

기본 명령은 대화형으로도 쓸 수 있습니다.

```bash
sh init.sh init ../my-project
sh init.sh list-profiles
```

이미 파일이 있는 프로젝트에 적용할 때는 의도적으로 `--force`를 붙여야 합니다. 이 옵션은 kit가 관리하는 같은 경로의 파일을 덮어쓸 수 있으므로, 기존 문서를 백업하거나 Git 상태를 먼저 확인하세요.

```bash
sh init.sh init ../existing-project --profile generic --force
```

## 구조

| 경로 | 역할 |
| --- | --- |
| `core/` | 모든 프로젝트에 복사되는 구현 워크플로우, Phase·Step 템플릿, 상태 관리 스크립트 |
| `profiles/` | Spring 백엔드, Next 웹처럼 자주 쓰는 기본값 |
| `templates/` | 프로젝트별로 채워 넣을 문서와 에이전트 지침 |
| `init.sh` | 프로필을 병합하고 새 프로젝트의 파일을 생성하는 POSIX 셸 CLI |

## 프로필

| 이름 | 기본값 |
| --- | --- |
| `generic` | 언어·프레임워크를 정하지 않는 최소 규칙 |
| `spring-backend` | Kotlin, Spring Boot, PostgreSQL, REST, 계층형 구조, TDD |
| `next-web` | TypeScript, Next.js App Router, React, Tailwind, 컴포넌트 테스트 |

프로필은 시작점일 뿐입니다. 생성 후 `harness.toml`과 문서를 프로젝트의 실제 상황에 맞게 수정하세요. 새 프로필은 `profiles/`에 TOML 파일을 추가하면 됩니다. `--set section.key=value`로 작은 차이도 초기 생성 시 반영할 수 있습니다.

```bash
sh init.sh init ../api \
  --profile spring-backend \
  --set stack.language=Java \
  --set architecture.style=hexagonal \
  --no-adr
```

## Codex와 Claude 호환

기본 산출물은 Codex를 포함한 에이전트 공통 지침인 `AGENTS.md`입니다. Claude도 함께 쓰는 프로젝트라면 `--claude-compat`을 추가해 `CLAUDE.md`를 생성할 수 있습니다. 이 파일은 중복 규칙을 갖지 않고 `AGENTS.md`를 우선 읽도록 안내합니다.

## 검증과 테스트

```bash
sh tests/test-init.sh
sh ../escape-log/scripts/verify-harness.sh ../escape-log
```

`verify-harness.sh`는 필수 파일, 문서 토큰, 설정 파일을 확인합니다. 제품 코드의 테스트나 린트 대신, 하네스 생성 상태만 점검합니다.
