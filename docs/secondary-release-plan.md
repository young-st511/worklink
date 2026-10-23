# 트랙패드 합성 release와 종료 연결 회수

## 영향 도메인·수용 기준

S40. 실제 사용자 입력 기록은 right down 직후 수 마이크로초 만에 right up이 전달되지만 pressedMouseButtons는2(계속 눌림)였습니다. 이 합성 up을 release로 단정하지 않습니다. 또한 단절 시 비동기로 닫던 소유 SSH를 UI 코어 종료 전에 기다려 이전 실행의 forward가 남지 않도록 합니다. 원본·클립보드 guard·타 프로세스/SSH 보호를 유지합니다.

## Step 1

- [x] 스펙→Red: 물리 눌림 중 합성up 업무0,0.5초long1/실제놓기short0, 짧은물리놓기short1, 제한시간/취소/오래된watcher 차단
- [x] 소유 아이콘의 합성up 동안에만 최대10초/30Hz release 확인, common 단발 예약·종료취소·상시polling없음
- [x] 단절 비동기Close와 engine loop drain을 Shutdown에서 기다리고 EOF/단절 종료 회귀 검증
- [x] native/Go race/vet/실제SSH·리뷰·문서·commit/push/원자설치, 임시 진단 제거

## 실행 규칙

stepped-plan-executor 하네스의 명세→Red→구현→검증→독립 스펙/코드 병렬 리뷰→수정/문서/commit/main push를 따릅니다. 리뷰만 위임합니다. 물리 입력 직접 조작은 CUA 거부를 우회하지 않고, 관측된 이벤트 순서·fixture 검증과 물리 재확인을 구분합니다. 원격/로컬 임시 fixture만 사용하고 앱은 자동 재시작하지 않습니다.


## 완료 결과

실제 기록 기반 합성up 회귀와 threshold 경합 Red→수정, 전체Go race/vet·native self-test·독립 스펙/코드 재리뷰·실제SSH 단절EOF 자식회수/파일/클립보드 회귀·서명/아이콘/plist/렌더를 통과했습니다. 이전 소유orphan2개만 검증후정리했습니다. 임시진단코드/파일을 제거하고 설치본을 원자교체했으며 주요7개 리소스hash/서명을 확인했습니다. 실제 물리 재확인은 미검증, 자동 재시작 없음입니다. 소스와 기록을 main에 반영합니다.
