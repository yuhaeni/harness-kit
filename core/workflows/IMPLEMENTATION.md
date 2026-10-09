# 공통 구현 워크플로우

이 문서는 `harness-kit`이 생성하는 프로젝트에서 공통으로 쓰는 작업 흐름이다. 프로젝트마다 달라지는 기술 선택·품질 기준·범위는 루트의 `harness.toml`과 `docs/`를 우선한다.

## 1. 이해

1. `AGENTS.md`, `harness.toml`, `docs/INTENT.md`, `docs/LLM_WIKI.md`를 읽는다.
2. 관련 요구사항과 기존 구현·테스트를 확인한다.
3. 불명확한 부분은 영향이 큰 가정만 사용자에게 확인하고, 나머지는 작업 결과에 가정으로 남긴다.

## 2. Phase 승인과 Step 정의

1. 구현 전에 Phase 문서에 설계·경계·Phase 수준 수용 기준을 작성한다.
2. 설계 승인을 받은 뒤에만 `harness phase create <phase> "제목" --approved`로 Phase를 만든다. 새 Phase의 최초 상태는 `approved`다.
3. 승인된 Phase에서만 `harness step create`로 Step과 `step-<id>-evidence.md`를 만든다. 새 Step의 최초 상태는 `planned`다.
4. `harness:next` 워크플로우(`harness next`)가 보여 주는 Step 중에서만 다음 작업을 고른다. 이 명령은 `planned`이며 모든 선행 Step이 `completed`인 Step만 출력한다.

## 3. 가장 작은 전달 단위 정의

작업을 구현 가능한 작은 단위로 나누고, 각 단위에 다음을 만든다.

- 변경 대상과 하지 않을 범위
- 관찰 가능한 수용 기준
- 검증 방법(테스트, 린트, 수동 확인 중 무엇인지)
- 데이터/API/의존성에 미치는 영향

독립적으로 출시하거나 검증할 수 없는 큰 변경은 이 기준으로 더 나눈다.

## 4. 구현과 상태 전이

1. 작업 시작: `harness step start <phase> <step>`으로 `planned → in-progress` 전이한다.
2. 프로젝트가 지정한 테스트 우선 개발 방식을 따른다.
3. 기존 구조와 명명 규칙을 우선하고, 현재 요구에 필요한 최소 변경만 한다.
4. 결정이 여러 기능이나 장기간의 유지보수에 영향을 주면 ADR을 남긴다.
5. 작업 중 발견한 문서와 구현의 불일치는 같은 변경에서 갱신한다.
6. 구현으로 검증된 구조·명령·계약·운영 사실을 `docs/LLM_WIKI.md`에 갱신한다.

## 5. 검증과 검토

1. 변경한 범위의 테스트·린트·빌드를 실행한다.
2. 테스트가 없거나 실행할 수 없다면 이유와 대체 검증을 명시한다.
3. 근거와 검증 결과를 해당 `step-<id>-evidence.md`에 기록한다.
4. `harness step review <phase> <step>`으로 `in-progress → review_required` 전이한다.
5. 리뷰 승인 시 `harness step complete <phase> <step>`으로 `review_required → completed` 전이한다.
6. 수정 요청 시 `harness step replan <phase> <step>`으로 `review_required → planned` 전이한다.
7. 하네스 자체의 상태는 `scripts/verify-harness.sh`로 별도 확인한다.
