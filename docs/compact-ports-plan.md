# 컴팩트 포트 목록

영향: Dashboard 포트 목록과 등록 안내 공간. spec S23 및 S19/S22 회귀, domain-contract의 수동 endpoint·실제 URL 보존·기존 업무/원본 규칙을 유지합니다.

## Step 1
- collapsed 행을 24 point 한 줄로, 포트 group 간격 3 point로 구성합니다. 상세는 chevron으로 펼치며 전체 주소/오류/원격 대상/주소복사/제목확인은 그 안에 유지합니다.
- 등록 안내를 고정 한 줄로 줄이고 관리 링크를 heading에 합칩니다. 빠른 등록 폼의 조상·입력·선택·IME와 고정 popup 크기를 유지합니다.
- native 실패 테스트 → 구현 → 1/5/8포트·상세 light/dark 렌더·native/Go 검증 → 두 병렬 리뷰 → 수정·문서·로컬 commit → /Applications 기존 설치 업데이트. 제품 앱 자동 재시작/CUA 우회/GitHub 작업 없음.
- [x] 완료

## 실행 규칙
기존 stepped-plan-executor harness mode의 spec-first native 검증, 두 병렬 리뷰, 문서/로컬 commit 규칙을 따릅니다. 기존 설치 승인을 적용합니다.
