# 개발 서버 주소 입력 파서

사용자가 확정한 서버 등록 UX의 설계입니다. 아직 실행 가능한 파서를 구현한 것은 아닙니다. 별도 의존성 없이 Go 표준 `net/url`, `net/netip`, `net.SplitHostPort`를 조합하는 작은 함수로 구현할 예정입니다.

## 세 종류의 주소를 구분

- SSH 대상: 접속할 원격 Mac의 별칭. 예: `office-mac`. 등록 화면에서 별도로 선택합니다.
- 원격 개발 서버 주소: 그 Mac의 `localhost:5173`, `127.0.0.1:5173`, `[::1]:5173`.
- 로컬 열기 URL: 집의 브라우저에서 사용할 터널 주소. 예: `http://localhost:15173/preview`.

LAN 주소나 Tailscale IP·호스트명도 접속 주소가 될 수 있지만, 현재 제품은 선택한 SSH 대상의 loopback 서비스만 전달합니다. 임의 LAN·외부 호스트를 조용히 localhost로 바꾸지 않습니다. 입력에서 SSH 대상까지 자동으로 추측하지 않습니다.

## 입력 예시

로컬 포트가 비어 있고 원격 포트와 같게 배정됐다는 가정입니다. IPv6 URL에는 대괄호를 유지합니다.

| 붙여넣은 값 | 정규화한 원격 주소 | 로컬 열기 URL |
| --- | --- | --- |
| `5173` | `127.0.0.1:5173` | `http://localhost:5173/` |
| `:5173` | `127.0.0.1:5173` | `http://localhost:5173/` |
| ` localhost:5173 ` | `127.0.0.1:5173` | `http://localhost:5173/` |
| `http://127.0.0.1:4387/preview` | `127.0.0.1:4387` | `http://localhost:4387/preview` |
| `https://localhost:8443/` | `127.0.0.1:8443` | `https://localhost:8443/` |
| `Local: http://localhost:5173/` | `127.0.0.1:5173` | `http://localhost:5173/` |
| `http://0.0.0.0:5173/` | `127.0.0.1:5173` | `http://localhost:5173/` |
| `http://[::]:5173/` | `[::1]:5173` | `http://[::1]:5173/` |
| `[::1]:5173/preview` | `[::1]:5173` | `http://[::1]:5173/preview` |

`0.0.0.0`/`::`는 모든 인터페이스에서 연결을 받는 바인딩 지정이므로 Worklink는 접속 대상을 `127.0.0.1`/`::1`로 정규화합니다. 서버 자체의 바인딩 설정을 바꾸는 처리는 아닙니다.

## 간단한 처리 순서

1. 앞뒤 공백, 입력 전체를 감싼 따옴표·백틱, 붙여넣은 로그의 ANSI 장식을 제거합니다. 경로 내부 문자와 query/fragment는 바꾸지 않습니다.
2. 텍스트 안의 `http://`/`https://` URL 후보를 추출합니다. 하나면 사용하고, 여러 개면 등록 화면에서 후보를 고르게 합니다. 후보가 없으면 포트 숫자·`:포트`·loopback `host:port` 형식으로 해석합니다.
3. 포트만 있으면 `localhost`, scheme이 없으면 `http`를 보완합니다. IPv6를 임의로 콜론 분할하지 않고 `[::1]:5173` 형식을 요구합니다.
4. 표준 URL 파서로 scheme·host·port·path·query·fragment를 나눕니다. host는 알려진 loopback/unspecified 표기만 정규화하고 HTTP/HTTPS 및 포트 범위를 확인합니다.
5. 포트가 없으면 추측해서 열지 않고 등록 화면에서 개발 서버 포트를 입력받습니다. 알 수 없는 호스트는 선택한 SSH 대상의 loopback 서비스와 맞지 않는다는 점을 설명하고 수정할 수 있게 합니다.
6. SSH 대상과 정규화한 원격 endpoint를 등록 미리보기에 표시합니다. 로컬 포트를 배정하고 scheme·path·query·fragment를 유지한 브라우저용 URL을 별도로 구성합니다.

반환값은 성공 시 구조화한 endpoint, 추가 입력 필요, 후보 선택 필요, 입력 오류 중 하나입니다. 입력 중에는 네트워크 연결·페이지 제목 조회·DNS 조회를 하지 않습니다. 등록 확정 후에 기존 연결 및 제목 조회 처리로 넘어갑니다.

## 확인할 사례

포트만 입력, scheme 생략, URL 주변 따옴표, 로그의 단일·복수 URL, IPv4/IPv6, wildcard 바인딩 표기, path/query/fragment, 로컬 포트 충돌, 동일 endpoint 중복 등록, 포트 누락, 범위 밖 포트, 알 수 없는 host를 확인합니다. 로컬 포트를 바꿔도 path/query/fragment가 사라지지 않아야 합니다.

## 공식 자료

URL 해석은 표준 파서에 맡기고 입력 보완만 Worklink의 작은 전처리 함수에서 수행합니다. [Go net/url](https://pkg.go.dev/net/url#Parse), [Go net](https://pkg.go.dev/net#SplitHostPort), [Go net/netip](https://pkg.go.dev/net/netip#Addr.IsLoopback)

localhost는 loopback을 가리키는 특수한 이름입니다. TCP의 unspecified address로 listen하면 해당 호스트의 사용 가능한 주소 전체에서 연결을 받을 수 있습니다. [RFC 6761](https://datatracker.ietf.org/doc/html/rfc6761#section-6.3), [Go Listen](https://pkg.go.dev/net#Listen)
