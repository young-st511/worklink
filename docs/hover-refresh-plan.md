# 호버 잔상과 상세 행 개선

S28 및 domain-contract를 따릅니다. UI만 변경하고 원본/SSH/설정은 유지합니다.

- [x] root별 단일 hover 소유권 및 실제 hitTest로 임시 겹침/재렌더 잔상 방지
- [x] URL·복사 아이콘·제목 확인 동일 24pt 행, 전체 URL tooltip 유지
- [x] 실패 native 테스트 → 구현 → 회귀/밝은·어두운 렌더 → 두 병렬 리뷰
- [x] 문서·로컬 커밋·/Applications atomic 갱신

실행 규칙: 기존 stepped-plan-executor 하네스에 따라 위 순서로 진행합니다. 실제 앱 CUA 거부를 우회하지 않으며 합성 검증과 실제 마우스 검증을 구분합니다. GitHub/실앱 재시작은 하지 않습니다.
