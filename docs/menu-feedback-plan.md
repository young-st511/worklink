# 메뉴 피드백 개선

영향: AppKit popup 및 status glyph. spec S19/S20/S21/S22. domain-contract의 원본·업무 ON/OFF·기존 SSH·무음 상태·개인정보/로컬 Git 제약을 유지합니다.

## Step 1
- 원본 유지 설정 변경은 header의 고정 설명만 갱신하고 기존 notice는 유지합니다. root의 fitting size 및 header 행 높이도 고정합니다.
- 비활성 최근 이미지 동작에 원인별 tooltip/accessibilityHelp를 제공하고 disabled action을 차단합니다.
- 팝업 개발 서버 영역에 SSH 선택·포트/URL·등록을 추가합니다. 기존 parser/SaveConfig revision 검증을 재사용하고 persistent form/scroll ancestry로 입력·커서/IME를 유지합니다. 성공만 draft를 비우고 오류는 inline으로 표시합니다. OFF에서도 등록합니다.
- 동일 canvas와 크기의 template 체인을 직접 벡터로 그립니다. OFF는 중심이 끊어진 체인, ON은 연결된 체인, pause/error는 작은 표시. 캐시된 glyph를 사용하고 polling은 추가하지 않습니다.
- spec-first native 실패 테스트 → 구현 → native/Go 검증/렌더 시각 확인 → 두 병렬 리뷰 → 수정/문서/로컬 commit → 사용자 이동 경로 /Applications의 기존 앱 업데이트. CUA 거부 우회/앱 자동 재시작 없음.
- [x] 완료

## 실행 규칙
stepped-plan-executor harness mode의 테스트·두 병렬 리뷰·문서·로컬 커밋을 따릅니다. 현재 설치/로컬 Git 승인에 따라 진행합니다. SSH 설정·원격 헬퍼·사용자 이미지·preferences는 설치로 변경하지 않습니다. GitHub/PR/push 없음.
