# Worklink 구현 계획

2026-10-06. 영향 도메인: Go 코어·SSH 연결·원격 inbox·macOS 메뉴바. 수용 기준: [spec](spec.md). 불변 규칙: [domain-contract](domain-contract.md).

## Step 1: CLI, 주소, 원격 저장·프로토콜
- 목표: 느슨한 주소 입력, 영속 설정, 원본 저장, 만료 정리, framed stdio RPC를 독립 실행 가능하게 구현.
- 변경 파일: `go.mod`, `cmd/worklink`, `internal/address`, `internal/model`, `internal/storage`, `internal/wire`, `internal/remote`.
- 테스트: 주소·프레임·원본 해시·ACK 재시도·정리 경계·잘못된 기록.
- 충족 기준: S1–S5.
- [x] Spec 기반 실패 테스트 → 구현 → 테스트 → 병렬 스펙/코드 리뷰 → 수정 → 로컬 커밋.

## Step 2: SSH와 로컬 엔진
- 목표: 전용 master, 포트 등록·복구, 원격 헬퍼 채널, 영속 전송 큐, UI stdio 명령.
- 변경 파일: `internal/transport`, `internal/engine`, CLI 확장, 통합 테스트.
- 테스트: 원본 전송·연결 취소·포트 충돌·OFF 정지·재시도·원격 EOF, 실제 SSH 가능 여부.
- 충족 기준: S6–S9.
- [x] Spec 기반 실패 테스트 → 구현 → 테스트 → 병렬 스펙/코드 리뷰 → 수정 → 로컬 커밋.

## Step 3: macOS 앱, 패키징, 최종 검증
- 목표: AppKit 메뉴바, 우클릭 토글, 무음 상태, 설정·주소 미리보기, 원본 클립보드, 최근 5개, 자동 시작, 일일 정리 설치 도구.
- 변경 파일: `macos`, `scripts`, `Makefile`, 사용·설치·검증 문서.
- 테스트: 네이티브 컨트롤/클립보드 경쟁/취소, 실제 AppKit 뷰 렌더링과 가능한 경우 화면 조작, 설치물 빌드·원본 byte 일치·자원 측정.
- 충족 기준: S10–S14.
- [x] 구현·실행 → 테스트 → 병렬 스펙/코드 리뷰 → 시각 검증 → 수정·재검증 → 로컬 커밋.

## 실행 규칙

각 Step은 Spec 기반 실패 테스트, 구현, 테스트, 두 SubAgent의 병렬 스펙 검증/코드 리뷰, 수정·재검증, 문서 동기화, 로컬 커밋 순서로 진행한다. 각 Step은 직전 Step에서 `worklink/step-N/...` 브랜치를 만든다 (`main/step-N`은 기존 main ref와 충돌). 사용자 지시에 따라 PR·remote·push는 하지 않는다. 이미 합의된 설계를 spec으로 사용하며 Step마다 승인 질문은 하지 않는다.

실제 이미지·SSH 설정·기존 터널·Zellij를 변경하지 않는다. 검증은 별도 데이터 디렉터리와 유한 수명의 프로세스를 사용한다. OS 로그인 항목과 원격 정리 작업은 설치 가능한 도구를 구현하되 사용자 환경에 자동 설치하지 않는다. 검증 불가 환경은 원인·대안과 함께 기록하고, 가능한 검증을 계속 수행한다.
