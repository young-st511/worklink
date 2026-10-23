# 이동 중 네트워크·저전력 정책

## 영향 도메인 / 수용 기준

S37. AppKit Network/ProcessInfo 이벤트와 Go 런타임 정책·deadline scheduler. 원본/ACK/클립보드·등록 대상·OFF 중지·소유 SSH만 종료 규칙을 유지합니다.

## Step 1: 통합 정책

- [x] 명세 기반 실패 테스트: LP30초/일반5초/빈대상60초, 무경로 no-op, 복구/backoff, 대기 이미지, 중복 수동 확인
- [x] 코어 environment·취소·상태와 다음 deadline 대기. low power 변경은 세션 보존. 새 체크와 cleanup15초 freshness 통합
- [x] NWPathMonitor 가동 범위 ON/비잠금, false 즉시/true3초 debounce, stale callback 방지, power notification 및 UI 설명·새로고침
- [x] Go race/vet·native reducer/수명/clipboard/렌더·실제 SSH 회귀, 두 병렬 리뷰·수정·문서·commit·push·설치

## 실행 규칙

stepped-plan-executor 하네스의 명세→실패 테스트→구현→검증→스펙/코드 독립 병렬 리뷰→수정/검증→문서·commit·main push를 따릅니다. 리뷰만 위임합니다. 실제 네트워크/Wi-Fi/잠금 상태를 조작하거나 사용자 파일을 사용하지 않고 fake-clock/path fixture를 사용합니다. 기존 CUA 거부를 우회하지 않고 AppKit offscreen과 실제 UI 검증을 구분합니다. 설치 앱은 원자 교체하고 자동 재시작하지 않습니다.


## 완료 결과

S37 구현·전체 Go race/vet·native self-test·아이콘/서명·실제 SSH/named pasteboard 회귀·4개 상태 렌더 확인·두 독립 재리뷰를 통과했습니다. loss 직전 전송 시작 경합과 장기 SSH context·만료 저장 실패 busy retry를 수정했습니다. `/Applications/Worklink.app`를 원자 교체하고 서명/주요7개 리소스 SHA256 일치를 확인했으며 자동 재시작하지 않았습니다. 최종 소스와 문서를 함께 main에 반영합니다.
