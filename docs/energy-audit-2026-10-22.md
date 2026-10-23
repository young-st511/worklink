# 배터리·DX 점검 (2026-10-22)

## 현재 실행본 짧은 관측

소스 검토 기준 `9aaa360`. 설치 앱을 재시작하거나 업무 상태·클립보드를 바꾸지 않고, 실행 중인 Worklink 프로세스 트리의 CPU 누적 시간과 RSS를 `ps`로 3초 간격·15회 관측했습니다. 측정 구간은 45.61초, CPU 시간 해상도는 0.01초입니다. 실제 실행 바이너리의 빌드 commit은 측정에 포함하지 않았습니다.

| 프로세스 | 구간 CPU 시간 | 평균 CPU / 한 코어 | 마지막 RSS |
| --- | ---: | ---: | ---: |
| AppKit 앱 | 0.06초 | 0.132% | 42.16 MiB |
| Go 코어 | 0.02초 | 0.044% | 11.66 MiB |
| SSH 2개 합계 | 0.01초 | 약0.022% | 1.41 MiB |
| 합계 | 0.09초 | 약0.197% | 55.23 MiB |

측정 시 등록 대상1개·활성화된 포트16개, 일일 정리 옵션 ON이 설정돼 있었습니다. 앱1개 및 자식 SSH2개가 실행 중이었습니다. 설정과 프로세스 관측이며 UI 업무 상태·팝업 열림 여부·전송 동작은 통제하지 않았습니다.

전원은 AC, 배터리는100%·충전 완료 상태였습니다. 따라서 배터리 소모율, 소비 전력, 개선 전후 절감률은 측정하지 않았습니다. RSS 합계는 공유 페이지를 중복 포함할 수 있으며 physical footprint나 peak가 아닙니다. 구간 중 생성·종료된 짧은 자식 프로세스, 원격 Mac, Tailscale·시스템 서비스의 비용은 이 수치에서 제외합니다. 이전 짧은 측정과 조건이 달라 성능 개선/악화 비교에는 사용할 수 없습니다.

## 코드와 회귀 확인

- 클립보드는 업무 ON에서1초·tolerance0.1초, changeCount가 바뀐 경우에만 내용을 처리합니다. OFF·잠금·절전·접근 거부 때 감시를 중지합니다 (`AppDelegate.update/observeClipboard/pause`).
- 코어의 서버 확인은 고정5초입니다. SSH 실패는 최대60초 backoff, 포트 충돌은10/20/40/60초 backoff를 사용합니다 (`Engine.loop/cycle/failedPeer`).
- 오프라인 대기 이미지의 무변경 jobs 저장과 동일 UI state 출력을 생략합니다. 활동 기록은 상태 전환·미저장 복구 때 저장하며, 일일 포트 정리는 기존 cycle과24시간 gate를 사용합니다 (`sendNext/newEventEmitter/recordPortChecks/cleanupPorts`).
- 파일은 명시적 전송이고 자동 오프라인 재시도를 하지 않습니다. 전송 진행률은 추가 타이머 없이 읽기 진행에 따라 최대 약2Hz로 표시합니다 (`SendFiles/sendFile`).
- 배터리 관련 기존 Go race 회귀(오프라인/만료/충돌 backoff/동일 상태/세대/일일 gate)를 재실행했습니다. 테스트는 논리적 호출·쓰기 방지의 검증이며 시스템 전력이나 실제 wakeup 횟수 측정은 아닙니다.

## 배터리 개선 후보

1. **저전력 모드 대응**: 고정5초 포트 확인을 저전력 모드·장기 비활성 포트에서15–30초로 완화하고 사용자 조작 시 즉시 확인합니다. `ProcessInfo.isLowPowerModeEnabled`와 전원 상태 알림을 사용할 수 있습니다. 다만15초 freshness를 사용하는 상한 교체/일일 정리와 수동 새로고침을 함께 설계해야 합니다. [Apple 공식 문서](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled)
2. **네트워크 변화 대응**: 네트워크 복구 이벤트를 재연결 계기로 사용하고 연결 경로가 없을 때 불필요한 SSH 시도를 줄입니다. `NWPathMonitor`는 네트워크 경로 변화 관찰 수단이며, 그 결과만으로 Tailscale이나 특정 SSH 대상의 도달성을 단정하지 않습니다. [Apple 공식 문서](https://developer.apple.com/documentation/network/nwpathmonitor)
3. **등록 포트가 없는 대상의 빈 check 감소**: 현재 이미지 대상만 있어도5초마다 빈 check RPC를 보냅니다. 작업이 없으면 긴 keepalive 간격을 사용하되 원격 헬퍼2분 lease와 SSH 단절 감지를 함께 유지해야 합니다.
4. **저장 실패 backoff**: 활동 기록이 dirty이거나 이미지 만료 저장이 실패한 경우 기존5초 cycle마다 쓰기를 재시도할 수 있습니다. 정상 유휴 부하는 아니지만 디스크 장애가 길어지면 재시도 간격을 늘릴 여지가 있습니다. 활동 이력의 fail-closed 보호는 유지해야 합니다.

Apple의 에너지 가이드는 불필요한 타이머를 줄이고, 필요한 경우 중지·tolerance·적절한 timeout을 사용하도록 안내합니다. [공식 가이드](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html)

## DX 개선 후보

- 단축키로 최근 완료 캡처의 원격 경로 복사·파일 선택을 실행해 반복 메뉴 접근을 줄입니다.
- 프로젝트별 포트/이름 프리셋을 명시적으로 가져옵니다. 전체 리스너 자동 발견 없이 수동 등록 원칙을 유지하고 개인 SSH 별칭은 프로젝트 공유 파일과 분리합니다.
- 수동 연결 진단에서 SSH/헬퍼/원격 포트/로컬 충돌 단계를 구분하고 복구 방법을 보여줍니다. 상시 추가 진단 polling은 피합니다.
- `make verify/install`과 설치본 빌드 정보 표시를 마련합니다. 현재 `scripts/install-local.sh`는 `~/Applications` 설치와 기존 앱 거부 방식이라 실제 `/Applications` 원자 갱신 흐름과 차이가 있습니다. 버전이 고정돼 있어 실행 중인 이전 빌드와 갱신된 설치본을 구별하기도 어렵습니다.

이번 점검에서는 동작과 확인 주기를 변경하지 않았습니다. 실제 배터리 개선 효과를 비교하려면 동일 포트·네트워크·전송 부하·화면 조건에서 ON/OFF 또는 개선 전후를 반복하고, CPU 외 실제 에너지·wakeup 측정을 포함해야 합니다.


후속 구현: 2026-10-23 S37에서 네트워크 안정화·무경로 중지, 저전력 모드 30초 확인, 빈 대상 60초 keepalive를 반영했습니다. [이동 중 네트워크·저전력 계획](network-power-plan.md)과 [검증 기록](validation.md)을 참고해 주세요. 위 실측은 변경 전 조건이며 새 정책의 배터리 절감률로 해석하지 않습니다.
