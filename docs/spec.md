# 구현 수용 기준

사용자가 확정한 요구사항을 구현 검증 가능한 항목으로 나눴습니다. 구현 후 소스와 검증 기록을 아래에 연결합니다.

- S1: 포트/URL/로그 단일 후보, IPv4/IPv6/wildcard 정규화, 누락·복수 후보 구분, path/query/fragment 보존.
- S2: 사용자 전용 디렉터리에 원자적 설정 저장, 검증된 SSH 별칭/고정 헬퍼 경로, 중복 endpoint/로컬 포트 거부.
- S3: 원본 스트리밍 저장·크기/hash 확인·원자적 완료, 동일 ID retry는 동일 경로, local ACK 후 삭제.
- S4: 관리 파일명과 기록이 일치한 24시간 지난 파일 정리, pin·최근·미완료·일반 파일 보존, dry-run.
- S5: 버전·길이 제한 framed stdio 프로토콜, 원격 hello/upload/list/exists/check/cleanup, EOF 종료.
- S6: 시스템 OpenSSH 전용 master와 persistent 헬퍼 채널. Compression=no, batch host-key 확인, timeout/cancel, 소유한 연결만 종료.
- S7: 등록 포트 연결·IPv4/IPv6 localhost·충돌 오류·재연결·등록 endpoint만 확인, title은 요청 기반 bounded HTTP.
- S8: 전송 직렬화·8개/256MiB 제한·64MiB 원본 상한 설정 가능, generation/host 고정·retry/ACK 복구·restart 자동 전송 금지.
- S9: UI 명령/상태 JSON stdio와 CLI. OFF에서 세션/정기 통신 정지, 재연결 backoff·인증 오류 반복 금지.
- S10: AppKit 메뉴바 좌클릭 목록/우클릭 토글·OFF dimmed+다른 모양·무음·최근 5개·브라우저 열기·접속 상세 펼치기.
- S11: 서버/SSH 대상 등록·편집·삭제·설정, 느슨한 입력 미리보기·오류/후보 선택, 수동 명칭 우선.
- S12: 네이티브 changeCount 1초 감지·원본 표현 보존·단일 작업·경쟁 시 clipboard 보존·잠금/절전 pause·접근 거부 상태.
- S13: 앱 번들에 Go 바이너리 포함·macOS 로그인 시작·일일 cleanup 설치/제거 도구, 개발 저장 공간 분리.
- S14: 코드 리뷰 수정 후 의미 있는 테스트·최종 빌드·시각 렌더 확인·설치/사용 문서·실제/불가 검증 구분.

## 현재 동작과 검증

S1–S5 구현: `internal/address.Parse`, `model.Config.Validate`, `storage.Store.Receive/Verify/Cleanup/SaveConfig`, `remote.Serve`, `wire.Read/Write`, `cmd/worklink.run`. 테스트와 양쪽 리뷰 통과. S3의 ACK 후 로컬 큐 삭제는 Step 2에서 검증합니다. 각 단계의 결과는 [validation](validation.md)에 기록합니다.

S6–S9 및 S3 로컬 ACK 후 삭제 구현: `transport.Connect/SSH.Call/Forward/Close`, `engine.Engine/ServeUI`, CLI `sendImage`. 원본 SHA-256·실제 SSH IPv4/IPv6 터널·제목·경로 재복사·OFF 종료, 취소·ACK 저장 실패·restart 회복·원래 대상 retry·queue orphan 한도 테스트와 양쪽 재리뷰 통과.

S10–S14 구현: `macos/AppDelegate`, `DashboardController`, `SettingsController`, `ClipboardReader`, `CoreBridge`, `install.CleanupPlist/CleanupJob/Remote`, `scripts/build-app.sh`. Go race/vet, native 회귀 테스트, 실제 SSH+named pasteboard 원본 PNG·경로 교체 및 AppKit 밝은/어두운/OFF/오류/설정 뷰 렌더 확인. 실제 마우스·브라우저 열기·권한·자동 시작·일일 작업 활성화는 환경 검증으로 남았으며 validation.md에 구분했습니다.

S10 팝업 레이아웃은 380×460 point로 고정하고 header/footer를 목록 스크롤 밖에 유지합니다. `DashboardController.render/resetScroll`, `AppDelegate.showMenu`와 native 회귀 테스트로 상태 전환·재열기 잘림을 보완했습니다.

## 클립보드 모드와 원본 복사 수용 기준

- S15: 메뉴바 `캡처 원본 유지` 선택은 재실행에도 유지, 초기 기본은 기존 자동 경로 복사. 전환은 클립보드·전송·업무 상태를 변경하지 않고 완료 시 현재 설정을 적용. 원본 유지 모드는 완료 시 byte·type·changeCount를 변경하지 않음.
- S16: 최근 완료 이미지의 `원본 복사`는 두 모드에서 원격 원본을 요청 시에만 가져와 동일 형식/byte로 클립보드에 기록. 새 내용·OFF·잠금·generation 변경 시 덮어쓰기 금지. 앱이 기록한 원본은 재업로드하지 않음. 만료/연결 오류 표시, 임시 다운로드 제거, 장기 로컬 복사본 없음. 명시적 경로 복사도 유지.

S15/S16 구현: `ClipboardPreferences.complete`, `AppDelegate.complete/copy/restore`, `DashboardController.render`, `Engine.RestoreOriginal`, `SSH.Download`, `remote.Serve(download)`. 다운로드는 기존 SSH master를 사용하는 요청별 임시 채널로 제어/업로드 RPC를 점유하지 않습니다. 원본 복사 후 lastCount 갱신으로 재전송을 막고 복사 뒤 scratch를 삭제합니다. 검증 결과는 validation.md에 기록합니다.

## macOS 앱 아이콘

- S17: Worklink 연결 모티프의 macOS 앱 아이콘을 Icon Composer 벡터 레이어와 실제 Liquid Glass 재질로 제작. 밝은/어두운/mono appearance 렌더 확인, 앱 번들 아이콘 등록·Assets.car·이전 macOS용 icns 포함. 기존 14 이상 런타임은 유지. 메뉴바 상태 glyph는 S21을 따릅니다.

S17 구현: `assets/Worklink.icon`, `scripts/build-icon.sh/build-legacy-icon.sh/render-icon.sh`, `build-app.sh` Info.plist 병합. native asset catalog의 IconImageStack 및 Aqua/DarkAqua/Tintable appearances, SVG vector layers와 고해상도 icon을 `verify-app-icon.py`로 확인합니다. native self-test는 icns decode 및 1024px 표현을 확인합니다.

## 실시간 다크 모드 전환

- S18: 열린 같은 팝업에서 appearance가 light→dark→light로 바뀔 때 글자와 배경이 함께 갱신됩니다. 재열기/업무 ON/OFF/새 state render를 요구하지 않습니다. 전환은 메뉴 크기·스크롤 위치·업무 상태를 바꾸지 않습니다.

S18 구현: `AppearanceBackgroundView.updateLayer/viewDidChangeEffectiveAppearance`, `DashboardController.loadView/render`. `nativeSelfTest`는 같은 window/view에서 state를 다시 render하지 않고 light→dark→light의 실제 bitmap 픽셀과 크기·스크롤·자식 identity 유지를 확인합니다. `renderPreviews`는 동일 view의 전환 3개 PNG를 생성합니다.

## 메뉴 높이·비활성 이유·상태 아이콘

- S19: `캡처 원본 유지` 전환은 기존 전송 알림을 덮어쓰거나 새 알림 행을 넣지 않고, 동일 상태/공지에서 팝업 외형·Auto Layout fitting 크기·header/footer·목록 위치를 유지합니다.
- S20: 최근 이미지 버튼이 업무 OFF·만료·전송 중·원본 가져오는 중·원래 대상 연결 대기 등으로 비활성화되면 짧은 이유를 native tooltip 및 접근성 도움말로 제공합니다. 비활성 동작은 실행하지 않습니다.
- S21: 메뉴바 ON/OFF 아이콘은 같은 18 point template canvas·체인 크기를 유지하고 원형 배경을 사용하지 않습니다. OFF는 끊어진 체인+기존 약한 dimming으로 구분합니다. 일시 정지/오류도 같은 체인에 작은 표시를 사용합니다.

- S22: 팝업 개발 서버 영역에서 포트·단일 localhost URL을 입력해 등록할 수 있습니다. 수동 등록한 SSH 대상 중 현재 이미지 대상을 기본 선택하고 다른 대상을 고를 수 있습니다. OFF에서도 등록하며 기존 parser/config revision 검증을 사용합니다. 완료 시 입력을 비우고 오류/중복/모호한 입력은 draft를 유지합니다. 주기적 상태 render 중 입력과 선택·커서/IME를 보존합니다. 추가 debounce polling/리스너 탐색은 없습니다.

S19–S22 구현: `AppDelegate.setClipboardMode/registerQuickPort/updateIcon`, `DashboardController.render/refreshQuickControls/disabledReason`, `ActionButton.setDisabledReason`, `MenuBarGlyph`. root/frame/fitting 및 header 행 크기 고정, notice 보존, 원인별 tooltip/accessibilityHelp, 고정 18 point template glyph, popup의 persistent SSH/포트 등록 폼과 기존 parse/save_config 경로를 사용합니다.

## 컴팩트한 포트 목록

- S23: 기본 포트 행은 상태점·이름·짧은 localhost 주소·상태·펼치기를 한 줄(24 point)에 표시합니다. 전체 URL과 오류는 tooltip 및 상세에서 확인하고, 주소/이름 클릭은 기존 URL의 scheme/path/query/fragment를 유지합니다. 포트 행 간 간격을 줄이고 관리 링크는 개발 서버 heading에 합칩니다. 빠른 등록 안내는 높이를 고정한 한 줄로 표시합니다. 5개 일반 포트가 기본 body viewport에 들어가고 팝업 크기·모드 전환·입력/cursor/IME 보존은 유지합니다.

S23 구현: `DashboardController.compactPortRow/render/quickForm`. 24 point 행/3 point gap, 전체 URL·오류 tooltip/펼친 상세, heading의 관리 링크와 고정 한 줄 안내를 사용합니다. `nativeSelfTest`는 일반 완료 notice가 있는 5개 포트의 viewport 적합·행 높이, HTTPS/path/query/fragment를 가진 브라우저 콜백·상세 동작을 확인합니다.

## 상단 한 줄 업무 제어

- S24: 제목·캡처 원본 유지 checkbox·눈에 띄는 업무 상태와 native ON/OFF switch를 한 줄에 배치합니다. 반복 안내 두 줄과 하단 중복 업무 버튼은 제거합니다. 기존 toggle callback/대상 미등록 안내/우클릭 전환·고정 팝업·원본 모드·빠른 등록/IME는 유지하고 설명은 tooltip/accessibility로 제공합니다.

S24 구현: `DashboardController.render/toggleWork`, `MenuWorkSwitch.acceptsFirstMouse`. 28 point header의 한 줄 title/원본 checkbox/고대비 굵은 업무 label·상태점/native switch와 tooltip을 사용하고 기존 toggle callback을 호출합니다. native self-test는 동일 title row·switch state/action/첫 클릭 정책·접근성 및 중복 footer 제거를 확인합니다.

## 등록 포트 IPv4/IPv6 자동 지원

- S25: 기존 등록과 새 localhost/127.0.0.1/[::1] 포트는 등록 주소를 먼저 확인하고 실패 시 다른 loopback family를 확인합니다. 둘 다 열렸으면 등록 주소를 우선합니다. 등록한 포트만 확인하며 실제 확인된 literal 주소로 양쪽 로컬 loopback SSH forward를 연결합니다. 서버 family가 바뀌면 소유한 해당 forward만 취소/재등록하고 오류는 재연결합니다. 다른 loopback IP는 지정 주소를 유지합니다. 실제 연결 주소는 상세에 표시하며 설정/ID/원본 동작은 보존합니다.

S25 구현: `Endpoint.Candidates/AllowsTarget`, `remote.Serve(check)`, `Engine.cycle/portStatus/failedPeer`, `PortStatus.remoteHost`, `DashboardController.compactPortRow`. check 응답의 literal target으로 forward하고 family 전환 실패 시 해당 host 포트의 ready를 무효화·publish합니다.

- S26: 최근 이미지 행은 한 줄 28 point로 시간·실제 작업 대상·용량·짧은 상태·작은 경로/원본 복사 버튼을 표시합니다. 전체 metadata(형식 포함)·오류·비활성 이유는 tooltip/accessibility로 유지합니다. 최근 5개, original copy/copy_path/retry callback·clipboard 준비됨 추적은 유지합니다. 일반 5개 이미지가 body viewport에 들어갑니다.

S26 구현: `DashboardController.render`의 28 point image row, metadata/state tooltip/AX와 compactAction icon-only control. 기존 copy/restore/retry와 copiedCount guard를 유지합니다. native self-test는 5개 viewport/행 높이·두 복사 callback·help를 확인합니다.

- S27: 활성 버튼의 hover 강조와 pointing cursor를 제공합니다. 포트 행에서 화살표 외 모든 영역은 같은 서버 열기 버튼으로 처리하며 연결 가능일 때만 활성화합니다. 상세 화살표는 별도의 버튼으로 유지합니다. 대기/OFF/충돌은 열기 비활성+이유 tooltip, 상세는 열 수 있습니다. 내부 표시 label은 click을 가로채지 않고 disabled hover/실행을 차단합니다. Dark mode·고정 행/팝업·quick editor/IME는 유지하며 polling을 추가하지 않습니다.

S27 구현: `ActionButton.updateTrackingAreas/mouseEntered/mouseExited/resetCursorRects/draw`, `PortDisplayStack.hitTest`, `DashboardController.compactPortRow`. 이벤트 기반 hover이며 추가 polling은 없습니다. `nativeSelfTest`는 행 여러 위치의 동일 hit target, 상세 분리, 실제 hover pixel 변화와 disabled hover/콜백 차단, OFF/대기/충돌 이유·상세 활성 유지를 확인합니다.

- S28: 상세 개폐·재렌더 후 호버는 같은 root의 실제 hit 대상 하나에만 적용하고 서로 다른 창의 재그림은 간섭하지 않습니다. 겹친 임시 frame/오래된 enter 상태가 여러 버튼을 강조하지 않도록 하고, 비활성·뷰 제거 시 해제합니다. 펼친 상세의 URL·주소 복사 아이콘·제목 확인을 동일 24 point 행에 배치하고 긴 URL은 tooltip/접근성으로 보존합니다.

S28 구현: `ActionButton.setHovered/synchronizeHover/viewWillMove/draw`, `DashboardController.compactPortRow`. root별 단일 weak hover 소유권과 content hitTest를 사용하며 상세 URL/action은 동일 24 point 행입니다. `nativeSelfTest`는 hover 소유권 이전과 상세 행 크기/복사 icon을 확인합니다.
