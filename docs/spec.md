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

- S17: Worklink 연결 모티프의 macOS 앱 아이콘을 Icon Composer 벡터 레이어와 실제 Liquid Glass 재질로 제작. 밝은/어두운/mono appearance 렌더 확인, 앱 번들 아이콘 등록·Assets.car·이전 macOS용 icns 포함. 기존 14 이상 런타임과 메뉴바 ON/OFF 아이콘은 유지.

S17 구현: `assets/Worklink.icon`, `scripts/build-icon.sh/build-legacy-icon.sh/render-icon.sh`, `build-app.sh` Info.plist 병합. native asset catalog의 IconImageStack 및 Aqua/DarkAqua/Tintable appearances, SVG vector layers와 고해상도 icon을 `verify-app-icon.py`로 확인합니다. native self-test는 icns decode 및 1024px 표현을 확인합니다.
