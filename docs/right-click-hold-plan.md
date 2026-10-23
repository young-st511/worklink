# 긴 우클릭으로 사진 모드 전환

## 영향 도메인·수용 기준

S38. 메뉴바 입력만 변경합니다. 원본·클립보드 guard·SSH·업무 세대는 유지하고, 짧은 우클릭의 기존 업무 토글과 긴 누르기를 구분합니다. 기존 domain-contract의 우클릭 1회 토글을 사용자가 승인한 긴 누르기 예외로 확장합니다.

## Step 1

- [x] 명세→실패 테스트: 0.5초 전 짧은 클릭1회, 누르는 중 긴 동작1회/뗄 때0회, 중복 down·취소·오래된 timer 차단
- [x] 메뉴바 drop overlay의 down/up/drag와 일회성 common-mode timer를 연결하고 잠금·절전·제거·종료 시 취소
- [x] 기존 모드 setter와 아이콘/tooltip/접근성 안내, native 회귀·렌더 및 두 독립 리뷰
- [x] 문서·commit·main push·설치, 제품 앱 자동 재시작 없음

## 실행 규칙

stepped-plan-executor 하네스의 명세→Red→구현→검증→스펙/코드 병렬 리뷰→수정/문서/commit/push를 따릅니다. 구현은 직접 수행하고 리뷰만 위임합니다. 테스트는 offscreen AppKit·별도 defaults/pasteboard를 사용하며 기존 CUA 거부를 우회하지 않습니다.


## 완료 결과

S38 native self-test(가짜 scheduler·실제 RunLoop·합성 뷰 이벤트), 전체 Go race/vet·아이콘·서명·plist·diff 검사와 밝은/어두운 모드 렌더 확인을 통과했습니다. 스펙/코드 독립 리뷰 모두 blocker 없음입니다. 코드 리뷰어의 추가 독립 번들 실행은 중단되어 결과를 합산하지 않습니다. 설치본을 원자 교체하고 주요7개 리소스 hash 일치를 확인했습니다. 제품 앱 자동 재시작·물리 메뉴바 입력 검증은 수행하지 않았습니다. 소스·문서를 함께 main에 반영합니다.
