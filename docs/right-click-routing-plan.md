# 메뉴바 우클릭 원시 이벤트 라우팅

## 영향 도메인·수용 기준

S39. S38의 실제 메뉴바에서 즉시 OFF가 되는 사용자 보고를 처리합니다. NSControl action 타이밍에 우클릭을 의존하지 않고 앱 내부 local event monitor로 해당 status 창·아이콘의 원시 down/up/drag만 소비합니다. 전역 입력 감시·반복 polling·클립보드 변경·세션 재시작은 추가하지 않습니다.

## Step 1

- [x] 스펙→실패 테스트: down만으로 업무 토글0, 긴 예약 전환1/up0, 짧은 up1, 타 창/밖 down 통과, drag취소/재진입·lifecycle/token 보호
- [x] local router·해제/취소·기존 overlay를 연결하고 button action은 좌클릭에만 사용
- [x] native/self-test·기존 모드/입력/파일 드롭 회귀·독립 스펙/코드 리뷰·서명·렌더
- [x] 문서·commit·push·원자 설치, 자동 재시작 없음

## 실행 규칙

stepped-plan-executor 하네스의 Red→구현→검증→병렬 독립 리뷰→수정/문서/commit/main push를 따릅니다. 리뷰만 위임합니다. 실제 메뉴바 물리 입력은 기존 CUA 거부를 우회하지 않고 offscreen fixture·합성 앱 이벤트와 구분합니다.


## 완료 결과

전체 Go race/vet·최종 native self-test(설치 local monitor와 앱 dispatch 포함)·아이콘/서명/plist·렌더·독립 스펙/코드 리뷰를 통과했습니다. 설치 앱을 원자 교체하고 주요7개 리소스 hash 일치를 확인했습니다. 실제 물리 메뉴바 입력은 미검증이며 자동 재시작하지 않았습니다. 소스와 검증 기록을 main에 함께 반영합니다.
