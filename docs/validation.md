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

## 메뉴 피드백과 팝업 빠른 등록

2026-10-06 사용자 피드백에 따라 S19–S22를 구현했습니다. 원본 유지 전환이 기존 notice를 덮어쓰거나 새 행을 추가하지 않으며 root frame/fitting size 380×460 point와 header 행 높이를 고정합니다. 최근 이미지의 비활성 이유를 `NSView.toolTip`과 접근성 도움말로 제공하고 disabled action을 차단합니다. 메뉴바는 같은 18 point template 체인을 사용하며 OFF는 중심이 끊어진 체인+65% alpha, pause/error는 작은 표시를 사용합니다. 새로운 폴링은 추가하지 않았습니다. tooltip과 template image 방식은 [Apple toolTip 문서](https://developer.apple.com/documentation/appkit/nsview/tooltip), [template image 문서](https://developer.apple.com/documentation/appkit/nsimage/istemplate)를 참고했습니다.

팝업 개발 서버 영역에 포트/localhost URL 입력·SSH 선택·등록/Enter를 추가했습니다. 기존 parser와 revision 검증을 사용하는 save_config를 재사용하며 OFF에서도 설정을 저장할 수 있습니다. 성공만 입력을 비우고 오류는 inline으로 표시합니다. scroll/document/stack/form의 조상을 유지하고 동적 행만 갱신하므로 입력을 중단시키지 않습니다.

- 구현 전 native 테스트에서 새 기능 미구현 compile 실패를 확인한 후 구현했습니다. native self-test, Go race/test/vet, 앱 아이콘 검사, diff 검사 통과.
- 원본 유지 true/false/true 전환의 frame/fitting/header/footer/목록 위치·기존 notice·clipboard changeCount 보존 검사 통과. 두 설명 상태와 동일 notice를 가진 실제 AppKit PNG에서 위치 변화를 확인했습니다.
- 업무 OFF·만료·전송 중·원본 가져오는 중·연결 대기·SSH 없음 등 disabled 이유와 접근성 help, disabled synthetic performClick 차단, 다시 활성화 시 도움말 제거를 확인했습니다.
- ON/OFF glyph의 동일 18 point canvas, 실제 alpha bounds 일치, 서로 다른 그림 및 filled 배경 없음 검사를 통과했습니다. 밝은/다크의 ON/OFF/pause/error glyph PNG를 열어 시각 확인했습니다.
- 별도 임시 Go core를 OFF로 실행해 Enter 경로의 URL 해석 및 config 저장, 대상/path/query/fragment 보존, 중복·non-loopback·여러 후보·포트 누락 거부, 오류 draft 보존, 중복 요청 차단을 확인했습니다. 운영 SSH·사용자 clipboard·로그인 항목·원격 서비스는 이 테스트에서 사용하지 않았습니다.
- 별도 native field editor에서 20회 render 중 동일 input/editor·커서·명시적 SSH 선택·조상 뷰 유지와 제약 누적 없음을 확인했습니다. Korean marked text/markedRange도 render 이후 보존되는 것을 확인했습니다. 실제 사용자 키보드 IME 조작을 테스트한 것은 아닙니다.
- 두 병렬 스펙/코드 리뷰 추가 blocker 없음. 코드 리뷰어는 최신 Swift 소스를 별도 임시 번들로 빌드해 전체 native self-test를 통과했습니다.
- 실제 메뉴바 마우스 클릭·disabled hover 툴팁 표시·제품 NSPopover 재열기 동작은 CUA의 앱 접근 거부로 자동 조작하지 않았습니다. native 기능/속성/field editor와 렌더 검증을 그 대체 완료로 주장하지 않습니다.

사용자가 옮긴 전체 사용자용 `/Applications/Worklink.app`의 기존 설치를 atomic 교체했습니다. 서명·Info.plist/실행 파일/아이콘/코어 hash와 아이콘 등록 검증을 통과했습니다. `~/Applications`에 새 복사본을 만들지 않았고 사용자 데이터·설정·원격 헬퍼는 변경하지 않았습니다. 제품 앱을 자동 재시작하지 않았습니다. 공개 소스 검수 통과, 로컬 Git만 사용했습니다.

## 컴팩트 포트 목록

2026-10-06 포트 목록을 collapsed 24 point 한 줄(dot/name/localhost:port/짧은 상태/chevron)과 3 point 간격으로 줄였습니다. 전체 URL 및 오류는 tooltip과 펼친 상세에 유지합니다. 관리 링크를 개발 서버 heading에 합치고 빠른 등록 안내는 높이가 고정된 한 줄로 줄였으며, 긴 안내는 tooltip으로 확인합니다. 일반 section 간격도 8 point로 줄였습니다.

- 구현 전 `port rows are not compact single lines` native 테스트 실패를 확인한 후 구현했습니다. 완료 notice가 있는 5개 일반 포트의 각 행 24 point·기본 viewport 포함 여부, HTTPS/path/query/fragment가 있는 실제 콜백 및 tooltip, 펼치기 후 주소 복사·제목 확인 유지 검사가 통과했습니다.
- 1/5/8개 포트와 펼친 상세의 light/dark AppKit PNG를 생성했습니다. 5개 목록·1개 목록·밝은/어두운 상세를 열어 잘림/겹침과 행 정렬을 시각 확인했습니다. 1개 포트에서는 최근 이미지의 복사 동작도 기본 화면에 보입니다.
- 기존 고정 크기·원본 유지 전환·native field editor/커서/IME·빠른 등록·disabled tooltip·glyph 검증, Go race/test/vet와 앱 아이콘 검증도 통과했습니다.
- 두 병렬 스펙/코드 리뷰 추가 blocker 없음. backend/통신/원본 처리 코드는 변경하지 않았습니다. 실제 제품 popup mouse·hover·브라우저 클릭은 CUA 접근 거부로 미검증이며 이를 다른 UI 조작으로 우회하지 않았습니다.

`/Applications`의 기존 설치를 atomic 교체하고 서명·빌드 hash를 확인했습니다. 사용자 설정·데이터·원격 헬퍼는 변경하지 않았습니다. 제품 앱 자동 재시작 및 GitHub 작업은 하지 않았습니다. 공개 소스 검수 통과.

## 상단 한 줄 업무 제어

2026-10-06 title과 원본 유지 checkbox의 같은 row 배치 및 더 명확한 업무 제어 피드백을 합쳤습니다. 90 point header를 28 point 한 줄로 줄이고 title·checkbox·상태점/고대비 굵은 ON/OFF label·native NSSwitch를 배치했습니다. 반복 안내 두 줄과 하단 중복 업무 버튼은 제거하고 tooltip/accessibility 도움말을 유지했습니다. 본문 viewport는 62 point 늘었으며 팝업 frame/fitting 크기는 그대로입니다.

- native 회귀 테스트를 먼저 추가해 `header controls are not in compact title row` 실패를 확인한 후 구현했습니다. same title row·28 point header·ON state·기존 toggle callback 1회·접근성 label·firstMouse 허용 정책·하단 중복 control 제거와 기존 전체 native self-test를 통과했습니다. 기존 대상 미등록 안내와 메뉴바 우클릭은 같은 AppDelegate.toggle 흐름을 사용합니다.
- NSSwitch는 isContinuous=false로 한 번의 변경을 전달하며 accessory popup에서 첫 mouse click을 허용합니다. [Apple NSSwitch 문서](https://developer.apple.com/documentation/appkit/nsswitch)와 [first mouse 문서](https://developer.apple.com/documentation/appkit/nsview/acceptsfirstmouse(for:))를 참고했습니다. 실제 첫 mouse click을 자동 검증한 것은 아닙니다.
- ON/OFF·원본 유지·1/5포트의 light/dark AppKit 렌더를 열어 한 줄 배치·상태 대비·잘림/겹침 없음과 더 넓어진 본문을 확인했습니다. Go race/test/vet·앱 아이콘 검사 통과. 두 병렬 리뷰 추가 blocker 없음. 코드 리뷰어는 최신 Swift 소스를 별도 임시 앱으로 빌드해 전체 native 테스트도 통과했습니다.
- 실제 시스템 외형/제품 popup mouse와 hover는 CUA 접근 거부로 미검증이며 우회하지 않았습니다. backend/SSH/원본 처리 코드는 변경하지 않았습니다.

`/Applications`의 기존 설치를 atomic 교체하고 서명·빌드 hash를 확인했습니다. 사용자 설정·전송 데이터는 변경하지 않았고 제품 앱 자동 재시작/GitHub 작업은 하지 않았습니다. 공개 소스 검수 통과.

## 등록 포트 dual loopback

2026-10-07 IPv6-only listener가 IPv4 등록에서 대기로 표시되는 사용자 사례를 해결했습니다. 등록 literal을 우선하고 실패 시 127.0.0.1/::1 중 다른 family를 확인합니다. 그 외 loopback은 지정 IP만 사용합니다. registered port당 최대 2회/각400ms, worker2로 제한하며 전체 listener 검색은 하지 않습니다. Targets/CheckErrors 응답은 optional로 추가하고 old-helper bool 응답은 기존 주소로 처리합니다.

check한 literal로 SSH forward를 생성하고 family 변경 시 같은 소유 forward를 취소/재등록합니다. waiting은 마지막 target을 유지합니다. 실제 주소를 native 상세에 IPv6 bracket 형식으로 표시합니다. 기존 설정/ID는 바꾸지 않습니다.

- Spec-first Go 테스트의 Targets/RemoteHost 미구현 실패 확인 후 구현. IPv4-only·IPv6-only·동시 listener preferred 순서, 실제 forward/cancel target, non-loopback 응답 거부, OFF/stale generation 상태 보호 검사 및 race/vet 통과.
- 실제 SSH 임시 HTTP fixture에서 IPv4→IPv6→IPv4 전환과 양쪽 local loopback·제목·원본 SHA·ACK 이후 큐 삭제·원본 다운로드를 확인했습니다. native named clipboard 두 모드에서 원본 유지/경로/원본 복사/no-reupload/scratch cleanup도 재검증 통과.
- 두 리뷰에서 retarget 취소 실패 시 오래된 ready가 남는 문제를 발견했습니다. 현재 peer/on guard 아래 해당 host의 포트를 waiting/reachable=false로 무효화하고 즉시 publish하도록 수정했습니다. retarget 실패 회귀 및 리뷰어의 이전 peer/OFF overlay 검증 통과, 추가 제품 blocker 없음.
- 반복 race 검증에서 기존 retry 테스트가 연결 호출만 기다려 Receive와 TempDir cleanup이 겹치는 경합을 발견해 실제 upload_complete/같은 ID·원래 host를 기다리게 강화했습니다. engine/remote race5회 및 vet 통과.
- 원격 helper를 갱신한 뒤 실제 운영 4000을 별도 임시 local port로 연결했습니다. 당시 실제 선택 주소는 127.0.0.1이었으며 양쪽 local loopback HTTP 응답을 확인했습니다. 앞선 IPv6-only 원인은 별도 fixture와 초기 listener 진단으로 구분하며, 운영 서버를 재시작하거나 설정을 변경하지 않았습니다.
- native 회귀/아이콘 검증 통과. 실제 popup mouse/hover는 CUA 거부로 미검증이며 우회하지 않았습니다.

/Applications 앱도 atomic 교체하고 서명·빌드 hash·공개 소스 검수를 통과했습니다. 제품 앱을 자동 재시작하지 않았으며 로컬 Git만 사용했습니다.

## 최근 이미지 한 줄 목록

2026-10-07 최근 이미지를 한 줄 28 point의 시간·실제 host·용량·짧은 상태와 작은 path/original/retry 아이콘 버튼으로 줄였습니다. full title/action·disabled 이유는 유지하고 metadata(형식 포함)/원래 상태/오류를 tooltip/accessibility로 제공합니다. 기존 copiedCount·clipboard guard·원본 처리 코드는 바꾸지 않았습니다.

- spec-first `image list is not compact` native 실패 후 구현. 한 줄 28 point와 5개 viewport 포함, 기존 path/original callbacks 및 tooltip, 기존 OFF/expiry/busy/accessibility/disabled actions와 원본 모드·field editor/IME·빠른 등록 등 native self-test 통과. Go race/test/vet·아이콘 검사·diff 검사도 통과했습니다.
- 5개 최근 이미지의 light/dark AppKit PNG를 열어 metadata/state/icon 배치와 잘림/겹침 없음을 확인했습니다. 실제 tooltip hover/mouse 클릭은 CUA 거부로 미검증이며 우회하지 않았습니다.

두 병렬 리뷰 추가 blocker 없음. 코드 리뷰어가 최신 Swift 소스를 별도 임시 앱으로 빌드해 native 검증을 통과했고 engine/remote race5회·vet·아이콘 검사도 통과했습니다.

/Applications 설치본을 atomic 교체하고 코드 서명·빌드 hash 및 공개 소스 검수를 확인했습니다. 사용자 설정·이미지 데이터·원격 helper는 이번 UI step에서 변경하지 않았고 앱 자동 재시작/GitHub 작업은 하지 않았습니다.


## 버튼 호버와 일관된 포트 클릭 영역

2026-10-07 활성 ActionButton에 마우스 enter/exit 기반의 accent 배경 강조와 pointing-hand cursor를 추가했습니다. 추가 폴링은 없습니다. 포트 행 왼쪽 320 point는 표시 이름·주소·상태를 담는 하나의 열기 버튼이고 오른쪽 24 point는 독립 상세 버튼입니다. 표시용 stack은 hitTest를 가로채지 않습니다. 연결 가능만 열기 활성화하며 업무 OFF·대기·충돌은 비활성 이유를 tooltip/accessibility로 유지합니다.

- spec-first 테스트에서 새 hover 속성 미구현 compile 실패를 확인한 뒤 구현했습니다. 여러 행 위치가 같은 open button을 반환하는 native hitTest, 상세 버튼 hit area 분리·브라우저 호출 없음, 전체 HTTPS URL 콜백 보존, 호버 전후 실제 bitmap pixel 변화·exit 해제·disabled hover/실행 차단을 확인했습니다.
- 업무 OFF·대기·충돌의 실제 port 버튼이 이유 tooltip을 가지고 열기를 차단하는 것과 상세 활성 유지 검사를 통과했습니다. 기존 고정 팝업·컴팩트 목록·입력 editor/IME·빠른 등록·clipboard/lifecycle/appearance native self-test도 통과했습니다.
- light/dark AppKit hover PNG를 열어 왼쪽 행 전체의 배경 강조와 별도 화살표 영역, 텍스트 대비·잘림/겹침 없음을 확인했습니다. Go race/test/vet·아이콘 검사·diff 검사 통과.
- 테스트는 별도 fixture의 직접 합성 handler 호출·hitTest·offscreen 렌더입니다. 실제 제품 mouse enter/exit·손 커서·툴팁·브라우저 클릭은 CUA 접근 거부로 미검증이며 다른 UI 자동화로 우회하지 않았습니다.

두 병렬 리뷰 추가 blocker 없음. 코드 리뷰어의 별도 임시 앱 빌드와 native self-test도 통과했습니다. `/Applications/Worklink.app`을 atomic 교체하고 서명과 Info/실행 파일/core/Assets.car/icns hash를 확인했습니다. 사용자 설정·이미지·원격 helper는 변경하지 않았으며 제품 앱 자동 재시작/GitHub 작업은 하지 않았습니다. 공개 소스 검수 통과.


## 호버 잔상과 상세 행 개선

2026-10-07 실제 사용자 화면에서 여러 버튼의 강조가 남는 문제를 확인했습니다. 이전 hover 상태가 버튼별로 독립되어 있었고 tracking 갱신 중 임시 frame 포함 검사에 의존했습니다. root별 단일 weak hover 소유권으로 이전 강조를 해제하고 실제 content hitTest를 통해 tracking 갱신과 visible draw 시 대상을 동기화합니다. 뷰 이동/제거와 비활성 전환에서도 해제하며 상태가 변경될 때만 다시 그립니다. 별도 polling은 없습니다.

- native `multiple buttons retain hover` 실패를 확인한 후 구현했습니다. hover 소유권 이전·disabled/exit·행 click target·기존 popup/editor/IME/clipboard/lifecycle 회귀 self-test 통과.
- 펼친 상세의 URL·주소 복사 아이콘·제목 확인을 동일 24 point 행으로 줄였습니다. 긴 URL tooltip/접근성 전체값과 복사 원문은 보존합니다. 행 높이/복사 icon native 검사 통과.
- light/dark 실제 AppKit 상세 PNG를 열어 정렬·대비·겹침 없음을 확인했습니다. Go race/test/vet·아이콘 검사·diff 검사 통과.
- 합성 handler와 offscreen 검증이며 실제 제품 마우스 이동/상세 클릭은 CUA 접근 거부로 미검증입니다. 다른 UI 자동화로 우회하지 않았습니다.

코드 리뷰에서 전역 hover 소유권이 서로 다른 창의 재그림을 연쇄시킬 수 있음을 발견해 root별 weak-to-weak map으로 범위를 제한했습니다. 독립 root의 상태 보존과 같은 root의 이전 해제, 부모 제거 후 해제 회귀 테스트를 추가했습니다. offscreen 부모 제거에는 window callback이 없어 테스트가 실패했으며 superview 이동 콜백에도 해제를 추가한 뒤 전체 native 검증이 통과했습니다.

두 병렬 리뷰 재검증 추가 blocker 없음. 코드 리뷰어의 최신 소스 독립 빌드/native 검증과 dark 렌더도 통과했습니다. `/Applications` 설치본을 atomic 교체하고 서명·빌드 hash·공개 소스 검수를 통과했습니다. 사용자 설정/원본/원격 helper 변경이나 제품 자동 재시작/GitHub 작업은 하지 않았습니다.


## 서버 표시 순서

2026-10-08 사용자 확인으로 실제 앱의 이전 호버 잔상이 해결되었음을 기록합니다. 메뉴 서버 행을 로컬 포트 번호 오름차순으로 정렬하며 같은 포트의 기존 순서는 보존합니다. 표시 시에만 정렬하고 config·SSH·연결/이미지 동작은 변경하지 않습니다. 기존 전체 native self-test로 회귀를 확인합니다.

Native self-test와 diff 검사를 통과했습니다. `/Applications/Worklink.app` 설치본을 atomic 갱신하고 서명·빌드 hash를 확인했습니다. 앱은 자동 재시작하지 않았으며 로컬 Git만 사용했습니다.


## 메뉴바 원본 유지 표시

2026-10-15 원본 유지 ON에 기존 체인 옆 테두리·산 모양 사진 표시를 추가했습니다. 기존 18pt 체인은 그대로 두고 canvas만 32×18pt로 늘립니다. OFF/ON/일시 정지/오류와 원본 유지 true/false의 8개 template을 캐시합니다. status item을 variableLength로 변경해 두 표시를 담으며 설정 callback에서 즉시 image/tooltip/접근성 값을 갱신합니다. 클립보드·원본 처리·SSH 로직과 추가 polling은 없습니다.

- spec-first native 테스트에서 새 API 미구현 compile 실패를 확인한 뒤 구현했습니다. 모든 mode에서 사진 표시 유무에 따른 체인 영역 2x alpha pixel 일치, 이미지 크기/template 속성, 사진 영역이 비어있지 않고 절반 미만을 채우는 선 그림인지 검사합니다. 원본 유지 전환·팝업·입력/IME·clipboard/lifecycle 등 기존 native 회귀도 확인합니다.
- 실제 point 크기의 light/dark AppKit strip을 열어 8개 조합의 체인 크기·분리된 사진 테두리와 산·오류/일시 정지 mark 및 OFF dimming을 확인했습니다. 실제 제품 메뉴바 조작/폭 변경은 CUA 접근 거부로 검증하지 않았으며 UI 자동화로 우회하지 않았습니다.

모든 native 회귀와 Go race/test/vet, 아이콘 검사, diff 검사 및 공개 소스 검수를 통과했습니다. 스펙 리뷰에서 사진 테두리 stroke가 canvas를 0.125pt 넘는 문제를 발견해 최대 x31.875pt로 안에 들도록 수정했고 재검증했습니다.

두 병렬 리뷰 추가 blocker 없음. 코드 리뷰어는 별도 glyph fixture의 1x/2x/3x 체인 픽셀 보존과 8개 캐시 동일성도 확인했습니다. `/Applications/Worklink.app`을 atomic 교체하고 서명·빌드 hash를 확인했습니다. 사용자 설정·원본·원격 helper는 변경하지 않았고 제품 앱 자동 재시작과 GitHub push는 하지 않았습니다.


## 사진 표시를 작은 배지로 변경

사용자 실제 메뉴바 피드백으로 S30의 나란한 사진 표시를 S31의 오른쪽 아래 배지로 대체했습니다. 모든 모드의 canvas를 기존 18×18pt로 통일하고 status item도 squareLength로 되돌렸습니다. 체인 크기/위치는 유지하고 원본 유지 ON일 때만 6.5×5.5pt 사진 테두리와 산을 표시합니다. keep ON에서는 오류/일시 정지 mark를 왼쪽 위로 옮겨 사진과 체인을 피합니다. 캐시·즉시 tooltip/접근성 갱신은 유지하고 클립보드·SSH 처리는 변경하지 않았습니다.

- spec-first native `photo indicator missing or clipped` 실패 확인 후 구현했습니다. 모드별 18pt/template, 배지와 이동한 상태 mark 영역 밖의 기존 픽셀 일치, 작지만 비어있거나 채워지지 않은 사진 선 그림 검사와 기존 native 회귀를 확인합니다.
- light/dark AppKit의 실제 point 크기 8조합 strip을 생성해 사진 배지의 위치와 크기·체인 보존·OFF dimming을 확인했습니다. 첫 렌더에서 왼쪽 아래 상태 mark가 체인에 가까워 왼쪽 위 빈 공간으로 옮겼습니다.
- 실제 제품 메뉴바 mouse/배치 조작은 CUA 접근 거부로 미검증이며 다른 UI 자동화로 우회하지 않았습니다.

Native 회귀·Go race/test/vet·아이콘 검사·diff 검사·공개 소스 검수와 두 병렬 리뷰를 통과했습니다. 코드 리뷰어는 별도 1x/2x/3x 검증으로 8개 18pt template과 상태 mark 이동을 확인했습니다. `/Applications/Worklink.app`을 atomic 교체하고 서명·빌드 hash를 확인했습니다. 사용자 설정·원본·원격 helper는 변경하지 않았고 앱 자동 재시작과 GitHub push는 하지 않았습니다.

사용자 후속 피드백으로 사진 배지 안을 작은 왼쪽 봉우리와 큰 오른쪽 봉우리 두 개로 변경했습니다. 배지 테두리·18pt canvas·체인·상태 표시는 유지하며 기존 native 회귀와 light/dark 실제 크기 렌더로 확인합니다.

두 봉우리 변경의 native self-test·diff 검사와 밝은/어두운 렌더 확인을 통과했고 `/Applications` 설치본의 서명·빌드 hash를 확인했습니다. 실제 메뉴바 마우스 조작과 앱 자동 재시작/GitHub push는 하지 않았습니다.
