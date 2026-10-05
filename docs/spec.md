# 구현 수용 기준

사용자가 확정한 요구사항을 구현 검증 가능한 항목으로 나눴습니다. 구현 후 소스와 검증 기록을 아래에 연결합니다.

- S1: 포트/URL/로그 단일 후보, IPv4/IPv6/wildcard 정규화, 누락·복수 후보 구분, path/query/fragment 보존.
- S2: 사용자 전용 디렉터리에 원자적 설정 저장, 검증된 SSH 별칭/고정 헬퍼 경로, 중복 endpoint/로컬 포트 거부.
- S3: 원본 스트리밍 저장·크기/hash 확인·원자적 완료, 동일 ID retry는 동일 경로, local ACK 후 삭제.
- S4: 관리 파일명과 기록이 일치한 24시간 지난 파일 정리, pin·최근·미완료·일반 파일 보존, dry-run.
- S5: 버전·길이 제한 framed stdio 프로토콜, 원격 hello/upload/list/exists/check/cleanup, EOF 종료.
- S6: 시스템 OpenSSH 전용 master와 persistent 헬퍼 채널. Compression=no, batch host-key 확인, timeout/cancel, 소유한 연결만 종료.
- S7: 등록 포트 연결·IPv4/IPv6 localhost·충돌 오류·재연결·등록 endpoint만 확인, title은 요청 기반 bounded HTTP.
- S8: 전송 직렬화·8개/64MiB 제한·16MiB 원본 상한 설정 가능, generation/host 고정·retry/ACK 복구·restart 자동 전송 금지.
- S9: UI 명령/상태 JSON stdio와 CLI. OFF에서 세션/정기 통신 정지, 재연결 backoff·인증 오류 반복 금지.
- S10: AppKit 메뉴바 좌클릭 목록/우클릭 토글·OFF dimmed+다른 모양·무음·최근 5개·브라우저 열기·접속 상세 펼치기.
- S11: 서버/SSH 대상 등록·편집·삭제·설정, 느슨한 입력 미리보기·오류/후보 선택, 수동 명칭 우선.
- S12: 네이티브 changeCount 1초 감지·원본 표현 보존·단일 작업·경쟁 시 clipboard 보존·잠금/절전 pause·접근 거부 상태.
- S13: 앱 번들에 Go 바이너리 포함·macOS 로그인 시작·일일 cleanup 설치/제거 도구, 개발 저장 공간 분리.
- S14: 코드 리뷰 수정 후 의미 있는 테스트·최종 빌드·시각 렌더 확인·설치/사용 문서·실제/불가 검증 구분.

## 현재 동작과 검증

S1–S5 구현: `internal/address.Parse`, `model.Config.Validate`, `storage.Store.Receive/Verify/Cleanup/SaveConfig`, `remote.Serve`, `wire.Read/Write`, `cmd/worklink.run`. 테스트와 양쪽 리뷰 통과. S3의 ACK 후 로컬 큐 삭제는 Step 2에서 검증합니다. 각 단계의 결과는 [validation](validation.md)에 기록합니다.
