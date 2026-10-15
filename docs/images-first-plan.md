# 최근 이미지 우선 배치

## 영향 도메인과 기준

메뉴바 UI, docs/spec.md S32와 domain-contract를 따릅니다. 원본/클립보드 guard·SSH·정리 규칙은 변경하지 않습니다.

## Step 1

대상: Dashboard.swift, Verification.swift 및 사용법/명세/검증 문서.
- [x] spec-first: 다수 포트에서도 3개 이미지 우선/초기 viewport, 펼침5/접기3/재열기3, 기존 콜백·입력/IME·popup 크기
- [x] 이미지 section을 개발 서버 위로 이동하고 제목 옆 전체 N개 보기/접기 구현
- [x] 8개 포트+5개 이미지 기본/펼침 light/dark native 렌더·회귀 검증
- [x] 두 병렬 명세/코드 리뷰와 수정·재검증 → 문서·로컬 커밋·/Applications 설치 갱신

## 실행 규칙

기존 stepped-plan-executor 하네스의 명세 → 실패 테스트 → 구현 → 검증 → 두 병렬 리뷰 → 문서·로컬 커밋 순서입니다. 현재 요청은 로컬 적용이며 push는 하지 않습니다. 실제 앱 CUA 거부를 우회하거나 앱을 자동 재시작하지 않으며 fixture 합성 이벤트/렌더와 실제 제품 마우스 검증을 구분합니다.
