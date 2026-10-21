# 오래된 포트 일일 자동 정리

## 영향 도메인과 수용 기준

S36, Go model/engine 및 AppKit 설정·팝업. 등록 대상만 확인, OFF 통신 중지, 기존 SSH/원격 프로세스 보존, 원본·ACK·클립보드 guard를 유지합니다. 설치와 push는 기존 사용자 승인 범위입니다.

## Step 1: 설정·정리·복원 통합

- [x] 기본OFF/7일 및 3·7·14·30일 정책, 포트 고정, backward-compatible Codable/config
- [x] 마지막 활성/최초 관측 기록, 최신 비활성·연결·세대 검증,24시간 gate, 고정/중지 보호
- [x] 기존 cycle에서 해당 forward만 해제, 다른 세션/파일 취소 없음. config와 정리/복원 기록 원자 저장·CAS·복원 충돌 보호
- [x] 설정 정책/고정 버튼, 팝업 결과/되돌리기, light/dark native 렌더 및 기존 입력/IME 회귀
- [x] fake-clock 경계·재시작·저장실패·취소/충돌·고정/상한 회귀, Go race/vet,두 독립 리뷰,문서·commit·push·설치

## 실행 규칙

stepped-plan-executor 하네스의 명세→실패 테스트→구현→검증→스펙/코드 두 병렬 리뷰→수정/재검증→문서·커밋·main push 순서입니다. 리뷰만 위임합니다. 실제 사용자 클립보드/데이터를 쓰지 않고 native fixture와 실제 제품 마우스 검증을 구분합니다. 기존 CUA 거부를 우회하지 않습니다. 설치본 교체 후 자동 앱 재시작은 하지 않습니다.
