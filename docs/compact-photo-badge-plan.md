# 작은 사진 배지

메뉴바 UI의 S31을 적용합니다. domain-contract의 클립보드·SSH·추가 polling 금지 제약은 유지합니다.

- [x] native 실패 테스트 → 모든 모드 18pt canvas, 오른쪽 아래 작은 테두리·산, 상태 mark 분리
- [x] light/dark 실제 크기 렌더와 기존 native 검증
- [x] 기존 stepped-plan-executor 하네스의 두 병렬 스펙/코드 리뷰 → 수정/검증 → 문서/로컬 커밋/설치 갱신

대상은 MenuBarGlyph.swift/main.swift/Verification.swift와 문서입니다. 사용자 요청은 로컬 적용이며 push는 하지 않습니다. 제품 CUA 거부를 우회하지 않으며 실제 UI 자동 재시작은 하지 않습니다.
