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


## 최근 이미지 우선 배치와 더 보기

최근 이미지 section을 개발 서버보다 위로 이동했습니다. 기본 최신 3개만 표시하고 더 있으면 제목 옆 전체 N개 보기/접기로 최대5개를 전환합니다. 상태 갱신 중 펼침을 유지하며 메뉴 재열기의 resetScroll에서는 기본3/맨위로 돌아옵니다. 데이터·전송·복사 guard와 포트 정렬은 바꾸지 않았습니다. 기존 quickForm ancestry를 유지해 입력/editor/IME 보존 구조도 그대로 사용합니다.

- spec-first native `image list is not compact` 실패로 기본3 미구현을 확인한 뒤 구현했습니다. 3개 기본과 5개 펼침/접기·refresh 유지·재열기 초기화, 다수 포트에서 이미지3개가 서버보다 위이면서 초기 viewport에 들어가는 검사와 0/1/3개에서 불필요한 버튼 없음 검사를 추가했습니다. 4개에서는 전체4개 보기로 정확한 개수를 표시합니다.
- 기존 포트5개가 모두 첫 화면에 맞아야 한다는 검사는 이미지 우선 정책에 맞춰 첫 서버 접근 가능 여부로 바꾸고 행 크기·주소 callback/상세 검사는 유지했습니다. 이미지 path/original callback과 기존 native 고정 popup/원본 전환/입력 editor/IME·빠른 등록·lifecycle 검사도 유지합니다.
- 8개 포트와 5개 이미지의 기본3/펼침5 light/dark 실제 AppKit PNG를 생성했습니다. 기본 다크와 펼친 밝은 렌더를 열어 이미지 우선·버튼·목록 정렬과 고정 헤더/푸터를 확인했습니다. 실제 제품 마우스·팝업 재열기는 CUA 접근 거부로 미검증이며 우회하지 않았습니다.

전체 native 회귀·Go race/test/vet·아이콘 검사·diff 검사·공개 소스 검수와 두 병렬 리뷰를 통과했습니다. 코드 리뷰어의 최신 소스 독립 빌드/native 검증도 통과했습니다. 이전 S23/S26의 동시 표시 기준은 S32 이미지 우선/기본3으로 명세를 동기화했습니다. `/Applications/Worklink.app`을 atomic 교체하고 서명·빌드 hash를 확인했습니다. 사용자 설정·원본·원격 helper는 변경하지 않았고 제품 앱 자동 재시작/GitHub push는 하지 않았습니다.


## 연결 장애 시 반복 작업 줄이기

2026-10-20 S33의 세 가지 범위를 구현했습니다. 호스트 재연결 backoff·네트워크 경로 이벤트·1초 클립보드 감시 정책은 이번 변경에 포함하지 않습니다.

- `power_test.go`를 먼저 작성해 새 emitter/clock 미구현 compile 실패를 확인한 뒤 구현했습니다. 연결 없는 큐를 60회 검사해 jobs.json inode/수정시각과 queued 상태·원본 파일이 그대로인 것을 확인합니다. 만료는 기록에 한 번 반영하고 반복 저장하지 않으며 저장 실패 후 재시도와 OFF/이전 generation의 변경 차단을 확인합니다. 연결 불가 host 뒤의 정상 host 전송도 ACK 완료됩니다.
- 동일 state 60회 입력이 출력1회로 줄어드는 것, reply/completion 각각2회는 그대로 출력되는 것, 작업 상태·업무 generation 변경은 새 상태로 전달되는 것, write 실패를 캐시해 다음 상태를 누락하지 않는 것을 검사합니다.
- 가상 시계로 충돌 포트의 10/20/40/60/60초 재시도와 마감 전 차단, 정상 포트 독립성·충돌 해소 복구·성공 후 재시도 없음·OFF 차단·원격 주소 family 변경 즉시 재시도를 확인합니다. 실제 사용자 네트워크를 끊지 않았습니다.
- 위 수치는 테스트의 작업/출력 횟수입니다. 앱 전체 전력·배터리 절감률을 실측한 결과로 해석하지 않습니다. 화면 배치 변경은 없습니다.

전체 Go race/test/vet·native self-test·아이콘 검사·diff 검사를 통과했습니다. 실제 SSH 임시 fixture에서 v4→v6→v4 전환/양쪽 로컬 loopback/제목/원본 SHA/ACK 뒤 큐 삭제/원본 다운로드/업무 OFF 종료를 재검증했습니다. 별도 named pasteboard의 원본 유지·경로 복사 두 모드에서도 수동 경로/원본 복사·재업로드 없음·scratch 삭제를 통과했습니다. 운영 네트워크·설정·이미지·헬퍼를 변경하지 않았습니다.


코드 리뷰에서 상태 중복 생략으로 로컬 클립보드의 준비됨 표시가 다음 render까지 남는 P2 회귀를 발견했습니다. named pasteboard에서 경로 복사 후 URL로 바꾸고 observeClipboard만 호출하는 테스트의 `no state heartbeat left stale ready marker` 실패를 확인했습니다. Dashboard의 준비됨 해제를 재사용 helper로 분리하고 기존 clipboard changeCount 감지에서 해제한 뒤 팝업이 보일 때만 render하도록 수정했습니다. 새 타이머나 state heartbeat는 추가하지 않았습니다. 변화 없는 클립보드에서는 표시가 유지되고 새 텍스트는 보존·재업로드하지 않는 것을 검사합니다.

P2 수정 후 native self-test와 실제 SSH/named pasteboard 두 모드 파이프라인도 재검증 통과했습니다. 두 병렬 재리뷰 추가 blocker 없음이며 코드 리뷰어의 독립 native 빌드와 전체 Go race/engine race10회/vet도 통과했습니다. 공개 소스 검수 후 `/Applications/Worklink.app`을 atomic 교체하고 서명·빌드 hash를 확인했습니다. 제품 앱 자동 재시작/GitHub push는 하지 않았습니다.

## 2026-10-21: 파일 전송과 포트 자동 교체

- S34: 명세 기반 실패 테스트 후 구현. 두 독립 리뷰에서 endpoint 변경 시 과거 비활성 기간 재사용, 저장 실패 뒤 활성 항목 오판 가능성을 찾아 수정했습니다. Host/Endpoint identity 검증·freshness 무효화와 재시작/SSH 단절/stale/세대/저장 실패 회귀를 포함합니다.
- S35: 명세 기반 storage/engine 실패 테스트 후 구현. SHA/빈 파일/한글 및 중복 이름/합산 quota/24시간 정리/취소·OFF/기록 실패 회귀를 포함합니다. 느린 파일 스트림 중 image Receive가 별도로 완료되는 동시성 테스트로 장시간 저장 잠금을 방지합니다. 전송 중 임시 파일과 rename-record 사이 비정상 종료 잔여물은 전용 staging 이름 또는 영속 pending 소유권 기록·일치하는 경로/이름/크기/해시·24시간 조건으로 정리하고 사용자 원본/알 수 없는 파일은 보존합니다.
- 실제 SSH 임시 디렉터리에서 일반 파일 batch 3개(한글·같은 basename·빈 파일)의 원본 SHA256/이름/별도 저장경로/경로 재복사를 확인했습니다. 기존 캡처 SHA/ACK/로컬 임시본 삭제/원본 다운로드·복사/원본 유지 양쪽 모드와 v4→v6→v4 tunnel 전환도 통과했습니다. 실제 사용자 파일은 사용하지 않았습니다.
- AppKit named pasteboard에서 file URL·legacy Finder 파일 목록 추출, Finder thumbnail 자동 캡처 제외, Services selector·드롭 타입 등록, 최근 파일 3→8개/경로 버튼을 검증했습니다. Light/dark 실제 AppKit offscreen 렌더를 확인했습니다. 기존 clipboard/lifecycle/appearance/hover/quick registration/editor/IME 테스트를 유지합니다.
- 실제 Finder 서비스 메뉴 노출·마우스 드래그·설치 앱 클릭 검증은 수행하지 않았습니다. 기존 Computer Use 접근 거부를 우회하지 않았으며, offscreen fixture/실제 SSH 검증과 구분합니다. 설치 앱 자동 재시작도 수행하지 않습니다.
- Apple 공식 API 근거: [Services Properties](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/properties.html)의 NSServices/NSMessage/NSSendFileTypes/NSRequiredContext 및 [NSDraggingDestination](https://developer.apple.com/documentation/appkit/nsdraggingdestination), [NSOpenPanel](https://developer.apple.com/documentation/appkit/nsopenpanel). 별도 Finder 확장 프로세스나 상주 polling을 추가하지 않습니다.
- 최종 `go test -race ./...`, `go vet ./...`, native self-test, 앱 서명/plist/아이콘 검사가 통과했습니다. 두 리뷰에서 지적된 연결 snapshot·기록 실패·느린 전송 잠금·히스토리 접근·소유권 정리 문제를 수정 후 재검증했습니다.
- 설치본 `/Applications/Worklink.app`를 원자적으로 교체하고 서명 및 주요 실행파일/리소스 SHA256을 검증했습니다. 선택된 원격 대상의 헬퍼를 갱신해 배포 바이너리 SHA256과 일일 정리 등록 성공을 확인했습니다. 제품 앱은 자동 재시작하지 않았습니다.

## 2026-10-22: N일 미사용 포트 일일 정리 (S36)

- 기본 OFF·7일/3·7·14·30일 선택, 최초 관측·마지막 활성 시각, 고정/중지/세대/단절/15초 freshness 보호,24시간 gate, 설정과 정리 이력의 원자 CAS 저장 및 전체 Undo 충돌 검증을 fake-clock 테스트로 확인했습니다. 정책 변경과 해당 forward 해제가 업무 세대·다른 SSH·파일 취소를 건드리지 않는 회귀를 포함합니다.
- 활동 기록은 지속 활성 체크마다 메모리 시각만 갱신하고 디스크는 상태 전환/미저장 복구 때만 씁니다. 최신 활성 관측 저장이 실패하면 메모리에 유지하고 저장 복구 전까지 정리·상한 교체를 차단합니다. 정리 오류는 현재 세대에서만 표시하고 기존 cycle에서 최소1분 뒤 재시도합니다. 추가 타이머·리스너 탐색·주기적 연결은 없습니다.
- 두 독립 리뷰에서 빈 이력의 Swift decoding, 느린 forward 해제 후 freshness 만료, 저장 실패 뒤 최근 활성 관측 유실, 이전 세대 오류 반영을 확인하고 수정했습니다. null/missing/[] CoreState·정책 기본값/기간·최근 실행·Undo/pin native fixture와 지연 forward/저장 실패 회귀를 추가했습니다.
- `go test -race ./...`, `go vet ./...`, native self-test와 밝은/어두운 cleanup popup AppKit offscreen 렌더를 검증했습니다. 기존 입력/cursor/IME·원본 클립보드·고정 팝업 회귀를 유지합니다. 실제 제품 마우스 조작은 수행하지 않았고 기존 CUA 거부를 우회하지 않았습니다.
- 최종 빌드로 실제 SSH 임시 fixture에서 기존 파일 batch(한글/동일 basename/빈 파일/원본 SHA/경로 재복사), 캡처 원본/ACK/원본 복사 양쪽 모드, v4→v6→v4 tunnel/title/OFF 회귀를 통과했습니다. 일일 정리 날짜·저장 실패·forward 경계 자체는 fake-clock/connection 테스트이며 실제 사용자 등록을 삭제하는 실험은 하지 않았습니다.
- `/Applications/Worklink.app`를 원자적으로 교체하고 앱 서명·주요 실행파일/리소스 SHA256을 검증했습니다. 기존 설정의 정책은 OFF로 유지하며 제품 앱은 자동 재시작하지 않았습니다.


## 2026-10-23: 이동 중 네트워크·저전력 정책 (S37)

- 일반5초/저전력30초/등록 포트 없는 대상60초 확인을 fake-clock/call-count로 검증했습니다. OFF·무경로는 timer 없는 이벤트 대기이며, 차단된 호스트의 대기 이미지는 온라인에서 만료 deadline을 유지하고 저장 실패는1분 뒤 재시도합니다. 수동 새로고침100회는2초 제한으로 합치며 재연결 대기와 recovery floor를 우회하지 않습니다.
- 경로 미확인 상태의 제품 코어 시작, 무경로 새 연결0회, loss의 진행 RPC/장기 transport 취소, 저전력 변화의 SSH·generation 유지, 이전 세대 guard, blocked/backoff 원인 보존을 검사했습니다. 이미지 exists RPC 도중 단절→같은ID·로컬원본 유지→복구 뒤 SHA/ACK 완료와 큐 회수를 검증했습니다. loss 직후 sendNext 시작 경합은 Red 재현 후 초기 mutex guard로 수정했습니다.
- 순수 native recovery gate에서 중복 이벤트100회·단절·오래된 token·OFF/재시작 콜백을 검사했습니다. NWPathMonitor는 업무 ON·비잠금/비절전에서만 시작하며 false 즉시/true3초 안정화 뒤 전달합니다. 중복 전원 알림을 생략하고 fatal core 종료 시 monitor/observer를 회수합니다. 전역 사용자 입력 감시와 추가 polling은 없습니다.
- 두 독립 스펙/코드 리뷰의 장기 SSH context 취소, 만료 저장 실패의 반복 루프, 손실 직전 전송 시작 경합 등을 수정하고 회귀를 추가했습니다. 전체 `go test -race ./...`·`go vet ./...`, native self-test, 아이콘·서명·plist·diff 검사를 통과했습니다.
- 최종 앱의 실제 SSH 임시 fixture에서 v4→v6→v4 tunnel/title/OFF, 일반파일 batch 원본 SHA/한글/동일 basename/빈 파일/경로 재복사, 캡처 원본 SHA/ACK/큐 삭제/원본 다운로드를 통과했습니다. native named pasteboard의 원본 유지/자동 경로 복사 양쪽 모드에서 수동 경로·원본 복사/재업로드 방지/scratch 삭제도 통과했습니다.
- 네트워크 대기·저전력 상태의 light/dark AppKit offscreen PNG 4개를 열어 상태 안내·새로고침/포트 활성화와 고정 레이아웃을 확인했습니다. 실제 제품 Wi-Fi·잠금·절전·마우스를 조작하지 않았고 기존 CUA 접근 거부를 우회하지 않았습니다. 실제 배터리 절감률과 가방 안 전체 시스템 전력은 측정하지 않았습니다.
- API 근거: Apple [NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor), [isLowPowerModeEnabled](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled). 네트워크 경로와 원격 Tailscale/SSH 도달성은 별도로 판단하며 경로 이벤트가 기존 backoff를 초기화하지 않습니다.

- `/Applications/Worklink.app`를 원자 교체하고 서명 및 주요7개 실행파일/리소스 SHA256 일치를 확인했습니다. 사용자 설정과 원격 운영 헬퍼는 변경하지 않았으며 제품 앱은 자동 재시작하지 않았습니다.


## 2026-10-23: 긴 우클릭으로 사진 모드 전환 (S38)

- 명세를 먼저 추가하고 `RightClickHold` 미구현 compile 실패를 확인한 뒤 구현했습니다. 가짜 scheduler에서0.5초 예약·중복 down·짧은 release·누르는 중 long1회·long 뒤 release0회·취소·늦은 callback·물리 버튼 해제·새 누르기의 token 격리를 검사합니다.
- 실제 main RunLoop 단발 timer에서0.2초에는 미실행,0.65초까지는 release 없이 long1회, 이후 release의 short0회를 확인했습니다. offscreen 메뉴바 입력 뷰의 합성 이벤트로 좌클릭/짧은 우클릭 분리·아이콘 밖 드래그·뷰 분리 취소를 확인했습니다. 전역 event monitor와 반복 timer는 추가하지 않았습니다.
- 기존 모드 setter의 별도 defaults/named pasteboard 검사(클립보드·안내·고정 header/footer/viewport 보존), 네이티브 lifecycle/입력/IME/파일 드롭·서비스·사진 glyph 회귀를 유지합니다. 전체 Go race/vet·native self-test·아이콘·서명·diff 검사를 통과하고 모드 ON의 AppKit offscreen 렌더를 열어 확인했습니다.
- 실제 메뉴바의 물리 우클릭·누르는 중 사진 배지 전환은 CUA 접근 거부로 미검증이며 우회하지 않았습니다. 이번 변경은 네이티브 입력만 다루므로 실제 SSH 회귀를 다시 실행하지 않았습니다. 직전 S37의 최종 bundled SSH/두 모드 전송 검증은 통과했습니다.

- `/Applications/Worklink.app`를 원자 교체하고 서명·주요7개 실행파일/리소스 SHA256 일치를 확인했습니다. 제품 앱은 자동 재시작하지 않았습니다.

- 스펙/코드 독립 리뷰에서 추가 blocker 없음입니다. 스펙 리뷰의 최신 native self-test는 통과했으며 코드 리뷰어의 추가 독립 번들 실행은 서버 중단으로 결과를 확인하지 못해 검증 결과에 포함하지 않습니다. 구현 담당자의 최종 native self-test·렌더·설치 검증은 완료됐습니다.


## 2026-10-23: 메뉴바 원시 우클릭 라우팅 수정 (S39)

- 사용자가 실제 메뉴바에서 우클릭을 누르자마자 업무가 꺼진다고 보고했습니다. 실행 시각과 설치본을 확인해 구버전 미재시작만으로 설명하지 않았으며, 실제 물리 입력 원인은 직접 재현하지 못했습니다. 버튼 action 기반 우클릭 경로를 제거하고 앱 내부 local event monitor가 해당 status 창/아이콘의 down/up/drag를 먼저 소비하도록 보강했습니다.
- `StatusRightEventRouter` 미구현 compile 실패 후 구현했습니다. 타 창/아이콘 밖 시작과 좌클릭 통과, down업무0·예약long1·긴up업무0·짧은up1, drag-out취소/재진입·lifecycle취소를 검사합니다. 설치된 local monitor에 offscreen `NSApp.sendEvent`를 보내 capture 상태와 실제 nil 소비에 의한 중복 동작 차단도 확인했습니다. 이전 S38의 핸들러 직접 호출·timer 검사만으로 실제 앱 dispatch까지 검증한 것으로 간주하지 않습니다.
- 전체 Go race/vet·최종 native self-test·AppKit 렌더·아이콘/서명/plist/diff 검사를 통과했습니다. 기존 모드 setter의 클립보드/generation/레이아웃 보존과 파일 드롭 회귀를 유지합니다. 실제 SSH를 변경하지 않아 이번에는 재실행하지 않았습니다.
- 실제 메뉴바 물리 입력은 기존 CUA 접근 거부로 미검증이며 우회하지 않았습니다. 따라서 사용자 보고의 물리 재현 완료나 모든 입력 장치에서의 해결을 주장하지 않습니다. 앱은 자동 재시작하지 않습니다.

- 두 독립 리뷰의 최신 임시 앱 번들 native self-test도 통과했습니다. `/Applications/Worklink.app`를 원자 교체하고 서명·주요7개 리소스 SHA256을 확인했습니다.


## 2026-10-23: 실제 트랙패드 합성 release·종료 후 포트 충돌 (S40)

- 사용자 진단 기록에서 raw right down 직후 약3마이크로초에 right up이 전달되지만 물리 버튼 상태는2(우측 눌림)로 유지되는 것을 확인했습니다. 기존 S38/S39는 이 up을 곧바로 짧은 클릭으로 처리해 업무를 전환했습니다. 실제 원인이 드러나기 전 synthetic-only 검사로 해결을 단정했던 한계를 인정하고 해당 이벤트 순서를 회귀에 추가했습니다. 실제 장치 전체의 동작을 일반화하지 않습니다.
- 이 합성up에서만 실제 놓임을30Hz 단발 예약으로 확인합니다.300회/uptime10초 상한이며 OFF/잠금/절전/종료/포인터 이탈·창 제거·오래된callback은 중지합니다. 일반클릭·유휴에는 추가 polling이 없습니다. 실제 누르는 동안0.5초 long1회, 놓은뒤short0·짧게놓기short1을 검사합니다.
- 두 리뷰에서0.5초 직전 실제 놓임을 long timer가 watcher보다 먼저 처리해 short가 유실되는 경계를 독립 재현했습니다. 실제 물리버튼/포인터 fixture와 long→watch 순서의 Red를 확인한 뒤, 내부 실제release는 short 완료하고 이탈은cancel로 분리해 수정했습니다. 독립 native 번들 전체 self-test와 engine race/vet 재리뷰를 통과했습니다.
- 포트 충돌은 이전 실행에서 남은 Worklink 전용 master2개가 포트를 점유하는 것으로 확인했습니다. 부모PID1·전용 임시socket·소유UID·실행옵션을 확인하고 해당 socket의 `ssh -O exit`만 실행해 정리했습니다. 사용자 SSH 설정/타 프로세스/원격 서버를 변경하거나 종료하지 않았습니다. 이후 현재 앱의 소유 master가 포트를 다시 점유하는 것으로 복구를 확인했습니다.
- 네트워크 loss가 peer를 detach한 뒤 비동기Close가 끝나기 전에 UI 코어가 종료할 수 있는 경계를 보완했습니다. 연결 중 loop·detached Close가 끝날 때까지 Shutdown이 기다리는 Red→race 회귀와 종료뒤ON거부를 검사합니다. 실제 SSH 임시fixture에서 OFF→ON→무경로→stdin EOF로 코어를 종료하고 미리 캡처한 소유 SSH 자식 PID가 모두 사라지는 것을 확인했습니다.
- 전체 Go race/vet·최종 native self-test·아이콘/서명/plist/diff·AppKit 렌더를 통과했습니다. 실제 SSH의 기존 tunnel v4/v6 전환·원본SHA/ACK/큐회수·일반파일batch·두 native클립보드모드 회귀도 통과했습니다. 임시 진단 코드를 최종 소스/앱에서 제거했으며 진단 원문은 커밋하지 않습니다.
- 실제 메뉴바에서 수정 후 물리 입력을 다시 누르는 동작은 미검증입니다. 기존 CUA 거부를 우회하지 않았고 앱은 자동 재시작하지 않습니다. 이 보완은 정상 UI 코어 EOF 종료를 다루며 SIGKILL·OS 강제종료 후 자동 orphan 탐색은 포함하지 않습니다.

- 최종 `/Applications/Worklink.app`를 원자 교체하고 주요7개 리소스 SHA256·서명을 확인했습니다. 임시 진단 원문 파일도 제거했습니다. 이전 실행의 연결을 정리하려면 이번 업데이트에서는 팝업 업무OFF 뒤 종료·재실행합니다.


## 2026-10-23: 네트워크 대기 glyph 숨김 (S41)

네트워크 대기만으로 메뉴바를 일시정지 모양으로 바꾸지 않습니다. 기존 업무ON/원본유지 배지는 유지하고 잠금/절전만 일시정지로 표시하며, 대기는 팝업·툴팁/접근성 설명에 남깁니다. 한 줄 상태 선택 변경을 직접 리뷰하고 기존 native self-test·Go race/vet·아이콘/서명/diff 검사와 glyph offscreen 렌더를 확인했습니다. 실제 메뉴바 조작은 별도 미검증입니다. `/Applications/Worklink.app`를 원자 교체하고 주요7개 리소스 hash/서명을 확인했으며 자동 재시작하지 않았습니다.


## 2026-10-26: 긴 우클릭 전환과 최신 캡처 바로 복사 (S42)

- 명세와 native 정책 테스트를 먼저 작성해 `ModeClipboardRequest` 미구현 compile 실패를 확인했습니다. 현재 대상 최신ID·미완료/nohost·mode revision·클립보드 count·generation·OFF/무경로·만료/단절을 검사하고 이전 사진으로 fallback하지 않습니다. 별도 defaults/named pasteboard의 설정만 변경·복사 차단을 검증합니다.
- 기존 수동 restore/copy의 원본byte·원격존재확인·scratch정리·lastCount를 재사용하고, 연속전환은 진행요청 종료 뒤 최신pending만 실행합니다. 일반 팝업 체크는 설정만 바꾸며 mode revision을 바꿔 이전 비동기 복사를 무효화합니다. 취소된 원본 가져오기는 진행 표시를 해제합니다.
- 두 리뷰에서 새캡처가1초감시 전이라 snapshot이 이전사진인 경계, 용량초과/스테이징/등록실패 후 lastCount만 갱신되어 이전사진을 선택하는 경계를 찾았습니다. 독립 재현과 본 담당의 Red를 확인하고 unregisteredCaptureCount marker를 읽기/용량/스테이징 전에 설정하도록 수정했습니다. marker는 현재boardcount 변경 또는 정확한replyjobID snapshot 관측으로만 해제합니다. 실패/업무OFF에서도 동일board내용을 보호하고 file URL 썸네일은 제외합니다.
- 최종 앱 실제SSH 임시fixture/named pasteboard의 자동복사·원본유지 두 초기모드 모두에서 긴전환 원본/경로 준비, 빠른3회 재전환의 최종원본, 직후 새텍스트복사 보존, 원본SHA·재업로드없음·scratch회수를 통과했습니다. 기존 일반파일batch/한글·동일basename·빈파일·경로재복사, v4/v6 tunnel/title, 단절EOF 소유SSH회수도 통과했습니다.
- 전체Go race/vet·최종 native self-test·아이콘/서명/plist/diff 검사와 AppKit 렌더를 확인했습니다. 두 독립 최종 리뷰의 최신 임시 앱 전체 native self-test도 통과했습니다. 실제 메뉴바 물리 긴누르기는 기존 검증과 구분하며 이번에는 조작하지 않았고 CUA 거부를 우회하지 않았습니다. 실제 사용자 클립보드·SSH설정을 변경하지 않았습니다.

- `/Applications/Worklink.app`를 원자 교체하고 주요7개 리소스 SHA256·서명을 확인했습니다. 제품 앱은 자동 재시작하지 않았습니다.
