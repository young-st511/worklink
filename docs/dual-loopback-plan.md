# 등록 포트 dual loopback

영향: remote check, engine forward, endpoint 후보와 native 상세. S25. 수동 등록 포트만 확인하고 기존 SSH master/원본/설정은 유지합니다.

## Step 1
- 127.0.0.1/::1에서 등록 주소 우선 + 다른 family fallback, bounded TCP 확인 2개/포트 이내. 응답에 targets/errors 추가, old helper 응답 fallback 유지.
- 확인된 literal로 forward; family 변경 시 같은 소유 forward를 취소/재등록. waiting은 마지막 target 유지. 원격 literal 응답 검증. 상세에 실제 연결 주소 표시.
- spec-first Go test → 구현 → race/vet/native/실제SSH IPv4-only·IPv6-only·family전환·운영4000별도localport검증 → 두 병렬 리뷰 → 문서/로컬 commit → /Applications 앱 및 기존 원격 helper 업데이트. CUA 우회/앱 자동 재시작 없음.
- [x] 완료

## 실행 규칙
기존 stepped-plan-executor harness mode, local Git/설치 승인에 따라 수행합니다. private 실제 주소/이미지/SSH 설정을 commit하지 않고 전체 리스너 검색·서버 재시작·네트워크 노출은 하지 않습니다.
