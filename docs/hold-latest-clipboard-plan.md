# 긴 우클릭 모드 전환과 최신 캡처 바로 복사

## 영향 도메인·수용 기준

S42. 긴 우클릭의 기존0.5초/트랙패드 처리·업무 의도는 유지합니다. 긴 누르기로 원본 유지ON이면 현재 이미지 대상의 최신 캡처 원본, OFF이면 그 이미지의 검증된 원격 경로를 기존 수동 복사 경로로 넣습니다. 일반 팝업 체크는 기존 설정 변경만 수행합니다. 원본 byte/ACK/새클립보드·업무세대 guard를 유지합니다.

## Step 1

- [x] 스펙→Red: 최신대상 선택·미완료/만료/nohost·OFF/단절 차단, 재전환/새캡처/대상변경/새복사 guard
- [x] 기존 restore/copy에 조건부 completion을 연결하고 긴 전환은 최신 요청만 직렬 실행, scratch 정리·lastCount 갱신으로 재업로드 방지
- [x] native self-test·실제SSH/named pasteboard 양방향 전환/빠른재전환·리뷰·렌더·문서
- [x] commit/main push·원자설치, 자동 재시작 없음

## 실행 규칙

stepped-plan-executor 하네스의 명세→Red→구현→검증→스펙/코드 병렬 독립리뷰→수정/문서/commit/push를 따릅니다. 리뷰만 위임합니다. 사용자 클립보드/네트워크/설정을 조작하지 않고 별도 defaults/named pasteboard와 임시 SSH fixture로 검증하며 CUA 거부를 우회하지 않습니다.


## 완료 결과

미관측/등록실패 새캡처의 old fallback 경계2건을 독립 재현·수정했고 최종 native/전체 Go race/vet·실제SSH/두 named clipboard 모드의 양방향·연속전환·새복사보호·재업로드없음·scratch회수 및 두 최종 독립 리뷰를 통과했습니다. 설치본을 원자교체하고 주요7개 리소스hash/서명을 확인했으며 자동 재시작하지 않았습니다. 실제 물리 긴누르기는 별도 미검증입니다. 소스와 문서를 main에 함께 반영합니다.
