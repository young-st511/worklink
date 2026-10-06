# 팝업 크기·스크롤 회귀 수정

영향 도메인: AppKit Dashboard/AppDelegate. 기준: domain-contract의 무음·원본 보존, spec S10/S14. 사용자 보고: ON/OFF·전송 기록 추가 후 팝업 높이 불일치, 재열기 시 상단 잘림.

## Step 1

- 목표: 380×460 point 고정 팝업, 상단/하단 고정, 중간 목록만 스크롤, 재열기 시 맨 위로 이동.
- 변경: macos/Dashboard.swift, main.swift, Verification.swift, 관련 검증 문서.
- 회귀 테스트: 빈 OFF → ON+기록 → OFF+기록 → 긴 목록/오류에서 같은 view/preferred size, 고정 header/footer 경계, 스크롤 초기화.
- [x] 실패 테스트 → 구현 → native 테스트/렌더 → 두 SubAgent 스펙·코드 리뷰 → 수정·재검증 → 로컬 커밋.

## 실행 규칙

이전 승인에 따라 로컬 Git만 사용하고 추가 승인 질문 없이 테스트·리뷰를 진행한다. 새 브랜치에서 수행한다. 실제 SSH 설정과 이미지·클립보드를 변경하지 않는다. CUA Worklink 접근 거부를 우회하지 않는다. 설치 파일은 업데이트하지만 실행 중 앱의 UI 재시작은 별도 사용자 조작이 필요할 수 있다.

클립보드 원본 문제는 별도 UX 선택으로 두고 선택 전 동작을 변경하지 않는다.
