# 검증 기록

2026-10-06 구현 진행 중. 기존 `measurements/`는 초기 실험이며 제품 성능으로 사용하지 않습니다.

## 환경

Go 1.26.4, Swift 6.4, macOS arm64. 네이티브 화면 제어 도구 첫 호출은 `Sky Computer Use native pipe startup failed`로 실패했습니다. 실제 앱을 만든 후 재시도하고, 별도로 앱 자체의 AppKit 뷰 렌더링으로 시각 확인을 수행합니다. 화면 제어 실패를 검증 성공으로 기록하지 않습니다.

## Step 1

- `go test -race ./...`, `go vet ./...`, CLI 빌드·별도 디렉터리 host/port 설정 시험 통과.
- 최초 주소 테스트는 구현 전 컴파일 실패(Red), 구현 후 IPv6 모호성 실패를 수정했습니다.
- 병렬 스펙·코드 리뷰에서 미완료 정리, 변조 파일 ACK, 설정 동시 저장 유실, query 문자 보존을 발견해 수정·재검증했습니다.
- 재리뷰: 양쪽 추가 blocker 없음. 설정 경쟁 재현은 성공한 등록 수와 실제 저장 수 일치.
- 기존 SSH 대상의 batch 접속과 Darwin arm64 확인. 아직 제품 SSH 전송은 Step 2 범위입니다. 실제 호스트 이름·계정은 기록하지 않았습니다.

## Step 2

- 실제 SSH의 별도 원격/로컬 임시 디렉터리에서 등록된 HTTP 터널, IPv4/IPv6 localhost, 요청 기반 제목, 원본 SHA-256 일치, 원본 유지, ACK 후 queue 삭제, 경로 재복사, OFF 종료를 확인했습니다. `scripts/ssh-integration.py`가 fixture를 정리합니다. 호스트 정보는 커밋하지 않았습니다.
- 리뷰에서 RPC 대기 취소, ACK 이후 종료 복구, 이전 호스트 retry, orphan queue 제한을 발견·수정했습니다. durable 완료 기록을 먼저 저장하고 그 다음 queue를 삭제합니다.
- 테스트는 완료 이벤트 후 queue 삭제를 확인하도록 수정했습니다. 리뷰어의 Go race 20회 반복 및 vet 통과, 두 관점 재리뷰 추가 blocker 없음.
- 일일 설치·메뉴바·네이티브 클립보드·시각 검증은 Step 3 범위입니다.
