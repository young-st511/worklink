# 메뉴바 원본 유지 표시

## 영향 도메인과 수용 기준

메뉴바 UI, docs/spec.md S30 및 domain-contract를 따릅니다. 사용자 원본·SSH·설정 구조는 유지하고 추가 polling은 없습니다.

## Step 1

- 변경 파일: MenuBarGlyph.swift, main.swift, Verification.swift 및 사용법/명세/검증 기록.
- [x] 원본 유지 ON에 체인 옆 테두리·산 사진 표시 추가, 기존 체인 크기/상태 표시 유지
- [x] 가변 메뉴바 폭과 설정 변경 즉시 이미지·tooltip·접근성 갱신
- [x] spec-first native 검증, 모든 상태·원본 유지 조합 light/dark 실제 크기 렌더
- [x] 두 병렬 스펙/코드 리뷰와 수정·검증 후 문서·로컬 커밋·기존 /Applications 설치 갱신

## 실행 규칙

기존 stepped-plan-executor 하네스의 명세 → 실패 테스트 → 구현 → 검증 → 두 병렬 리뷰 → 수정·재검증 → 문서·로컬 커밋을 따릅니다. 현재 요청은 로컬 앱에 적용하는 범위로 진행하며 GitHub push는 하지 않습니다. CUA 접근 거부를 우회하거나 앱을 자동 재시작하지 않으며 offscreen 렌더와 실제 메뉴바 마우스 검증을 구분합니다.
