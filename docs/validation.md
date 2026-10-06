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

## 클립보드 완료 모드와 원본 복사

2026-10-06 사용자 결정에 따라 메뉴 상단 `캡처 원본 유지` 전환(로컬 preferences 저장, 초기 기본은 기존 자동 경로 복사)과 최근 완료 이미지 `원본 복사`를 추가했습니다. 자동 전송은 유지하며 진행 중 작업은 완료 때 현재 모드를 적용합니다. 수동 경로 복사와 원본 복사는 요청 시 changeCount·업무 generation·ON/잠금 상태를 확인합니다. 원본 다운로드는 요청별 임시 SSH helper 채널에서 수행하며 기존 master를 공유합니다.

- 구현 전 원본 보존/모드 저장/native 원본 복사 테스트의 미구현 빌드 실패, 원격 download 테스트의 미지원 응답, Engine.RestoreOriginal 테스트의 미구현 실패를 확인한 후 구현했습니다.
- Go race/test/vet, native self-test, 실제 SSH와 named pasteboard 통합 QA 통과. 자동 경로 모드와 원본 유지 모드 각각에서 원본 SHA-256, 완료 시 clipboard 정책, 명시적 경로 복사, 원본 복사, 감지 타이머 2회 이후 재업로드 없음, 다운로드 scratch 삭제를 확인했습니다. 기존 IPv4/IPv6 터널·HTML 제목·ACK 후 큐 삭제·OFF 종료도 통과했습니다.
- PNG/JPEG(jpg·jpeg)/TIFF/HEIC/HEIF/WebP의 원본 복사는 해당 pasteboard type의 같은 byte를 기록하는 native 테스트로 확인했습니다. 실제 SSH+native end-to-end는 PNG로 검증했으며 타 앱의 각 형식 해석을 보장하지 않습니다. 테스트의 임의 JPEG/HEIC byte를 generic reader로 읽던 과정은 OS format promise 변환 때문에 unreadable이었으므로 해당 원본 type의 byte를 직접 확인하도록 수정했습니다.
- 두 병렬 리뷰에서 발견한 기존 전송 큐의 nil 연결 검사 회귀와 jpeg 확장자 별칭 누락을 수정하고 회귀 테스트를 추가했습니다. 최종 두 리뷰 추가 blocker 없음. 코드 리뷰어의 별도 임시 overlay 테스트는 다운로드 중 OFF, 동시 원본 복사 거부, 해시 불일치 거부 및 실패 scratch 삭제를 확인했으며 Go race 5회 반복도 통과했습니다.
- 실제 AppKit 밝은/어두운 원본 유지/자동 경로/최근 5개 목록 뷰를 렌더·시각 확인했습니다. 고정 380×460 point와 pinned header/footer·재열기 reset 회귀 테스트도 통과했습니다. 길어진 목록만 스크롤합니다.
- 로컬 설치 번들은 atomic 교체 후 codesign 검증과 빌드 바이너리 hash 일치 확인을 완료했습니다. 등록된 원격 헬퍼도 갱신했습니다. 운영 preferences·SSH 설정·이미지·포트 등록 정보는 repo에 저장하지 않았습니다.
- 실제 메뉴 클릭/재열기는 CUA의 Worklink 접근 거부 때문에 자동 조작으로 검증하지 못했고 이를 다른 UI 자동화로 우회하지 않았습니다. 실행 중 제품 앱도 자동 재시작하지 않았으므로 메뉴에서 종료 후 재실행해야 새 UI가 적용됩니다. GitHub 생성/push/배포 없음.

## Liquid Glass 앱 아이콘

2026-10-06 Worklink 앱 아이콘을 자체 SVG 연결 고리 2개와 Icon Composer 레이어로 제작했습니다. Apple 공식 제작 안내·Xcode macOS 기본 .icon 템플릿·공식 Landmarks 예제의 문서 구조를 참고했으며 샘플 아트워크는 사용하지 않았습니다. 실제 제작 파일과 재생성 방법은 assets/README.md에 기록했습니다.

- Xcode 27.0, macOS 27.0.1의 Apple actool/ictool/iconutil로 컴파일·렌더했습니다. native app icon 등록 검사를 먼저 추가해 기존 번들의 미등록 실패를 확인했습니다.
- native Assets.car의 실제 SVG Vector 2개, Aqua/DarkAqua/Tintable IconImageStack 3개와 1024px 아이콘을 assetutil로 확인했습니다. `verify-app-icon.py`가 번들 CFBundleIconName/File 등록과 실제 compiled artifact를 검사합니다.
- AppKit NSImage 및 ImageIO로 icns 로딩·고해상도 표현을 확인합니다. actool이 만든 icns stub은 16/128 point만 포함하므로, 별도로 Apple renderer에서 16/32/128/256/512 point의 1x/2x 표현 10개를 생성해 iconutil로 패키징했습니다. 앱에는 이 완전한 icns를 포함합니다.
- Default/Dark/ClearLight/ClearDark/TintedLight/TintedDark 및 16/32/64 point의 실제 Apple renderer 결과를 생성하고 기본·다크·투명·틴트·작은 크기를 열어 시각 확인했습니다.
- legacy 강제 빌드 후 native 빌드로 전환하는 두 실제 빌드 경로에서 native self-test와 아이콘 검사를 통과했습니다. stale Assets.car와 아이콘 메타데이터 제거를 확인했습니다. Go race/test/vet 및 shell syntax 검사도 통과했습니다.
- macOS 14 최소 타깃과 fallback 구성·icns 리소스를 확인한 것이며 실제 macOS 14 머신 실행을 검증한 것은 아닙니다. 메뉴바 ON/OFF 아이콘과 앱 업무 동작은 변경하지 않았습니다.
- CUA에서 Icon Composer 접근이 거부되어 화면 조작 대신 Apple CLI 컴파일/렌더를 사용했습니다. 제품 앱의 실제 Finder/Dock 표시·외형 모드 전환·아이콘 캐시 갱신은 자동 UI 조작으로 검증하지 않았습니다.

두 병렬 스펙/코드 리뷰 추가 blocker 없음. 코드 리뷰어가 별도 legacy 번들·공백을 포함한 리소스 경로·stale catalog 제거·서명 전 실패 중단을 확인했습니다. 설치된 앱은 atomic 교체 후 코드 서명·Info.plist/Assets.car/icns/실행 파일 hash 및 native 아이콘 등록 검증을 통과했습니다. 사용자 설정/전송 데이터/원격 헬퍼는 변경하지 않았으며 실행 중 제품 앱의 자동 재시작도 수행하지 않았습니다.

## 실시간 다크 모드 배경 갱신

2026-10-06 사용자 보고와 같은 고정 배경을 동일 view/window의 appearance 전환 테스트로 재현했습니다. 기존 `DashboardController.render`가 동적 NSColor를 CGColor로 한 번 해석해 CALayer에 보관하여 외형 전환 때 배경이 갱신되지 않았습니다. [Apple 다크 모드 공식 안내](https://developer.apple.com/documentation/uikit/supporting-dark-mode-in-your-interface)의 updateLayer 권고를 따라 root를 AppearanceBackgroundView로 바꾸고 effectiveAppearance 아래에서 배경색을 다시 해석합니다. appearance 변경 시에는 화면 갱신만 요청합니다.

- 회귀 테스트를 먼저 작성해 `live appearance background did not follow window` 실패를 확인한 후 수정했습니다. 새 state render 없이 같은 NSWindow/view를 Aqua→DarkAqua→Aqua로 바꾼 실제 bitmap 배경 픽셀 검사, view appearance·크기·스크롤·자식 identity 검사 통과.
- 동일 view를 유지한 전환 3개 PNG를 생성·열어 배경과 글자·버튼의 색상 변화, 고정 크기와 레이아웃을 시각 확인했습니다. 기존 light/dark/ON/OFF/설정 preview와 native self-test, Go race/test/vet, 앱 아이콘 리소스 검사도 통과했습니다.
- 두 병렬 스펙/코드 리뷰 추가 blocker 없음. 초기 표시·재열기·기존 state render의 배경 갱신 경로를 검토했습니다. 업무·원본 클립보드·SSH 코드는 변경하지 않았습니다.
- 테스트 window의 appearance 전환을 검증한 것이며 실제 macOS 시스템 외형 설정 토글이나 제품 팝업 마우스 조작을 확인한 것은 아닙니다. CUA 접근 거부를 우회하지 않았습니다.

설치된 앱을 atomic 교체하고 서명과 빌드 파일 hash를 확인했습니다. 사용자 설정·전송 데이터·원격 헬퍼는 그대로 두었으며 실행 중 제품 앱을 자동 재시작하지 않았습니다. 공개 소스 검수 통과, local Git만 사용했습니다.
