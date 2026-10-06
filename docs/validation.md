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

## Step 3

- AppKit 번들 빌드·ad-hoc 코드 서명 확인, arm64/amd64 원격 Go 헬퍼 포함.
- native self-test: PNG/TIFF 원본 바이트, size 제한, clipboard changeCount 및 OFF 보호, URL raw path/query/fragment와 한글 query/path, sleep/lock 겹침, 오래된 붙여넣기 준비 표시 제거, EOF 이벤트 중지, 종료 후 요청 실패 콜백 통과.
- 스펙/코드 리뷰에서 Unicode URL setter 크래시, EOF busy loop, 잠금 상태의 성급한 복귀, port 수정의 enabled/title 유실, SSH 편집 상태 잔류, 종료 후 요청 cleanup 누락 등을 발견·수정했습니다. 최종 두 관점 리뷰 추가 blocker 없음.
- 실제 SSH 임시 fixture에서 AppDelegate → named pasteboard PNG 캡처 → CoreBridge → Go 엔진 → 원격 저장 → SHA-256 일치 → named pasteboard 경로 교체를 확인했습니다. 사용자 일반 클립보드와 실제 이미지는 사용하지 않았습니다.
- 실제 AppKit 뷰를 `--render-previews`로 PNG 렌더링하고 light/dark, ON/OFF, 포트 충돌, 클립보드 변경, 서버/SSH 등록 화면을 열어 시각 확인·수정·재렌더했습니다. `.build/previews/`에 보관합니다. 웹/ASCII로 UI를 대신 만든 결과가 아닙니다.
- CUA 도구는 최초 inventory와 새 개발 앱 직접 선택에서 두 번 `Sky Computer Use native pipe startup failed`. 실제 마우스 우클릭·포커스·기본 브라우저 실행은 자동 조작으로 검증하지 못했습니다. 렌더와 named-pasteboard 검증을 그 대체 완료로 주장하지 않습니다.
- OS의 일반 클립보드 접근 허용·로그인 항목 승인·실제 잠금/절전 이벤트·LaunchAgent 활성화는 실제 사용자 시스템 설정을 변경하지 않기 위해 미검증입니다. 설치 도구의 XML escape·일일 schedule·dry-run은 테스트했고, 임시 inbox의 정리/만료/pin은 Go 테스트로 확인했습니다.

## 자원 측정

`measurements/native-off.json`: 약 30초 OFF 상태를 ps로 1초마다 관찰, 초기 3초 제외 26샘플. Swift 앱과 직접 Go 자식 2개 합산 평균 CPU 샘플 0.00385%, 최대 0.1%, 평균 RSS 62.92 MiB·최대 63.14 MiB. ps는 짧은 burst를 놓칠 수 있고 RSS는 공유 페이지를 중복 계산할 수 있습니다. 전력/배터리/업무 ON/장시간 메모리/4K 100회 스트레스는 이 측정에서 입증하지 않았습니다. 초기 7.5 MiB clipboard CLI 수치를 제품 메모리로 사용하지 않았습니다.

## 최종 사용자 확인 권장

로컬 Mac에서 설치 후 첫 OS 접근 허용, 우클릭 토글, 캡처와 붙여넣기 1회, 포트 충돌 대체 주소와 브라우저/HMR, 잠금·절전 복귀, 다음 날 일일 정리 동작을 확인합니다. 설치·사용·정리 제거 방법은 getting-started.md를 따릅니다. 공개 repo 생성·push·배포는 하지 않았습니다.

## 팝업 크기 회귀 수정

2026-10-06 사용자 화면에서 ON/OFF와 전송 기록 갱신 시 높이 불일치 및 재열기 상단 잘림을 확인했습니다. 고정 380×460 point와 header/footer 고정, 목록 전용 스크롤, showMenu top reset 및 contentSize 동기화를 구현했습니다. 회귀 테스트를 먼저 추가해 구현 전 빌드 실패를 확인하고, 구현 후 native self-test와 밝은/어두운/OFF/오류 렌더 확인을 통과했습니다. 코드 리뷰어의 실제 AppKit harness는 긴 서버 목록 100회 render에서 크기·스크롤 위치 보존, 제약 누적 없음, 고정 영역 겹침 없음을 확인했습니다. 두 리뷰 추가 blocker 없음. 기존 클립보드 정책은 옵션 선택 전이므로 변경하지 않았습니다. 실제 메뉴 클릭/재열기는 CUA 접근 거부로 자동 검증하지 못했습니다.
