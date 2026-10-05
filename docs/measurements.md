# 초기 측정

측정일: 2026-10-05. 현재 접근 가능한 Mac에서 수행한 작은 타당성 실험입니다. 집·사무실 양쪽 환경이나 제품 앱 전체를 시험한 결과가 아닙니다.

## 환경과 실행

- macOS 27.0.1, arm64, 물리 메모리 16 GiB.
- Apple Swift 6.4, `swiftc -O` 최적화 빌드.
- 각 클립보드 실험 30초, 1초 간격, 0.1초 tolerance, 순차 실행.
- 두 모드 모두 시작 시 `NSPasteboard.general.changeCount`를 한 번 읽어 AppKit 초기화 조건을 맞췄습니다.
- CPU 측정은 초기화 후 시작하며 메모리는 프로세스 전체 생애의 peak RSS입니다.
- 측정 중 기록된 클립보드 변경은 0회입니다. 실험이 클립보드 내용을 읽거나 변경하지 않습니다.

```sh
make probe
.build/clipboard-cost timer-only 30 1 > measurements/timer-only-1s.json
.build/clipboard-cost clipboard 30 1 > measurements/clipboard-1s.json
python3 experiments/listener-cost.py > measurements/listener-5s.json
```

마지막 실험은 Python 3가 필요하며, 로컬의 현재 사용자 소유 TCP 리스너를 `lsof`로 5초 간격·6회 조회하고 30초 뒤 종료합니다. 결과 목록은 버리고 자원 수치와 종료 코드만 기록합니다. 실제 서버로 네트워크 연결을 시도하지 않습니다. 원격 SSH 연결도 없습니다.

## 클립보드 결과

| 실험 | 실행 중 CPU 시간 | 평균 CPU, 한 코어 기준 | 최대 RSS | 타이머 콜백 |
| --- | ---: | ---: | ---: | ---: |
| 타이머만 실행 | 0.002037초 | 0.00679% | 7.45 MiB | 30 |
| 변경 번호 확인 | 0.002008초 | 0.00669% | 7.50 MiB | 30 |

원본: [timer-only JSON](../measurements/timer-only-1s.json), [clipboard JSON](../measurements/clipboard-1s.json).

두 수치의 차이는 매우 작고 한 번씩의 짧은 실험입니다. 변경 번호 확인이 타이머만 실행하는 것보다 빠르다는 의미는 아닙니다. 현재 환경에서 이 프로세스의 유휴 감지 비용이 작은 수준이었다는 근거로만 사용합니다.

## 리스너 검색 결과

5초 간격의 `lsof` 6회는 모두 종료 코드 0으로 완료했습니다. Python 측정 하네스 CPU는 0.007139초, `lsof` 자식 프로세스 합계 CPU는 0.095726초였으며, 30초 동안의 합산 평균은 **0.34285% / 한 코어**였습니다.

Python 부모 프로세스의 최대 RSS는 16.25 MiB, `lsof` 자식의 최대 RSS는 2.23 MiB였습니다. 이는 각각의 peak이며 같은 순간의 합계 메모리가 아닙니다. Python 하네스 메모리를 Go 헬퍼 메모리 추정에 사용하지 않습니다. 원본: [listener JSON](../measurements/listener-5s.json).

현재 환경에서는 주기적 리스너 검색이 변경 번호 확인보다 더 많은 CPU를 사용했습니다. 서로 다른 프로세스 구성의 단일 실험이므로 정확한 성능 배수나 다른 Mac의 사용량으로 해석하지 않습니다. 등록 방식 우선, 자동 발견은 선택형이라는 설계를 뒷받침하는 참고 결과입니다.

## 측정 한계

- CPU는 `getrusage`의 해당 프로세스 사용자/커널 CPU 시간입니다. pasteboard 서버 등 다른 시스템 프로세스가 대신 수행한 작업은 포함하지 않습니다.
- 최대 RSS는 현재 RSS, physical footprint, 이미지 변환 시 메모리 또는 전체 앱 프로세스 트리 사용량이 아닙니다.
- 타이머 콜백 30회가 시스템 wakeup 30회를 뜻하지 않습니다. 타이머 tolerance로 다른 활동과 묶일 수 있습니다.
- Swift CLI는 실제 서명된 메뉴바 앱과 권한·App Nap·프로세스 구성이 다릅니다.
- 이미지 타입 검사·내용 읽기·변환·해싱·전송, Go 런타임, SSH 연결, Tailscale 및 브라우저 요청은 클립보드 실험에서 제외했습니다.
- `lsof` 비용은 실행 중인 프로세스와 소켓 수에 따라 달라집니다. 로컬 결과를 사무실 Mac 성능으로 일반화하지 않습니다.
- 전력·배터리 소비량은 측정하지 않았습니다. 낮은 CPU 수치만으로 저전력을 보장하지 않습니다.

## 제품 검증에서 추가할 것

1. 각 Mac에서 30분 유휴와 실제 업무 1시간을 기존 스크립트/Worklink 조건으로 비교합니다.
2. 실제 signed 앱에서 클립보드 권한, 4K 이미지 변환·동시 복사·클립보드 도구 충돌을 확인합니다.
3. 직접 연결/DERP 경유 환경의 전송 지연과 자원 사용을 구분합니다.
4. Activity Monitor/Instruments로 시스템 에너지·Idle Wake Ups·physical footprint를 관찰합니다.
5. 포트 발견은 등록 방식과 5초/15초 소켓 열거를 비교한 뒤 기본값을 정합니다.

Apple은 타이머 중지·tolerance와 실제 에너지 도구 사용을 안내하고 있습니다. Go 코어가 생기면 공식 진단 도구로 CPU·heap·blocking 비용도 확인합니다. [Apple 에너지 가이드](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html), [Go Diagnostics](https://go.dev/doc/diagnostics)
