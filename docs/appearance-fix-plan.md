# 실시간 appearance 배경 갱신

영향: AppKit 팝업 배경. spec S18, domain-contract의 메뉴 상태·크기·기존 업무 동작을 유지합니다.

## Step 1
- 기존 root layer의 고정 CGColor를 appearance에 맞게 updateLayer에서 다시 해석합니다.
- 같은 NSWindow/view를 유지해 light→dark→light로 변경하고 render 없이 실제 bitmap 배경과 글자 appearance 갱신을 확인하는 회귀 테스트를 먼저 추가합니다.
- native self-test/전환 전후 실제 렌더 → 두 병렬 리뷰 → 재검증 → 문서·로컬 커밋·설치 파일 업데이트. CUA 거부를 우회하지 않으며 제품 앱/시스템 외형은 자동 조작하지 않습니다.
- [x] 완료

## 실행 규칙
기존 stepped-plan-executor harness mode의 spec-first 테스트, 두 병렬 리뷰, 문서/로컬 커밋 규칙을 따릅니다. 현재 로컬 Git 및 설치 승인을 적용하고 push/PR는 하지 않습니다.
