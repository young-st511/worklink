# 연결 장애 시 불필요한 작업 줄이기

## 영향 도메인

Go engine/UI 전송. docs/spec.md S33, domain-contract의 원본/ACK·OFF 중지·등록 대상만 관리·사용자 SSH 설정 보존을 따릅니다.

## Step 1

대상: internal/engine/engine.go, ui.go, 새 power_test.go, macos/Dashboard.swift/main.swift/Verification.swift, 사용법·명세·검증 문서.
- [x] spec-first: 대기 반복 사이클의 파일 동일성/상태, 만료 1회 저장, 다른 정상 host 작업 진행, 동일 state 중복 생략과 reply/completion 보존
- [x] 상태 heartbeat 없는 로컬 clipboard 준비됨 표시 회귀와 수정
- [x] 충돌 포트 10/20/40/60초 재시도, 정상 포트 독립성/충돌 복구/대상 변경/OFF 검사
- [x] 구현과 Go race/vet·native·필요한 실제 SSH 임시 fixture 검증
- [x] 두 병렬 명세/코드 리뷰 → 수정·검증 → 문서·로컬 커밋·기존 설치본 갱신

## 실행 규칙

stepped-plan-executor 하네스의 명세→실패 테스트→구현→검증→두 병렬 리뷰→문서·로컬 커밋을 따릅니다. 이번 요청은 로컬 적용이며 push는 하지 않습니다. 네트워크를 실제 끊거나 제품 CUA 접근을 우회하지 않습니다. 임시 저장 공간과 fake connector/시계를 사용하고 전력 실측과 작업 횟수 검증을 구분합니다.
