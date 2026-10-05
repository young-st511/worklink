package address

import (
	"fmt"
	"net"
	"net/netip"
	"net/url"
	"regexp"
	"strconv"
	"strings"
)

type Endpoint struct {
	Scheme      string `json:"scheme"`
	RemoteHost  string `json:"remote_host"`
	RemotePort  int    `json:"remote_port"`
	Path        string `json:"path"`
	RawPath     string `json:"raw_path,omitempty"`
	Query       string `json:"query,omitempty"`
	Fragment    string `json:"fragment,omitempty"`
	RawFragment string `json:"raw_fragment,omitempty"`
}

func (e Endpoint) LocalURL(port int) string {
	return (&url.URL{Scheme: e.Scheme, Host: net.JoinHostPort("localhost", strconv.Itoa(port)), Path: e.Path, RawPath: e.RawPath, RawQuery: e.Query, Fragment: e.Fragment, RawFragment: e.RawFragment}).String()
}
func (e Endpoint) Address() string { return net.JoinHostPort(e.RemoteHost, strconv.Itoa(e.RemotePort)) }

type Result struct {
	Endpoint   Endpoint `json:"endpoint"`
	Error      string   `json:"error,omitempty"`
	NeedsPort  bool     `json:"needs_port,omitempty"`
	Candidates []string `json:"candidates,omitempty"`
}

var ansi = regexp.MustCompile(`\x1b\[[0-?]*[ -/]*[@-~]`)
var urls = regexp.MustCompile(`(?i)https?://[^\s<>"` + "`" + `]+`)
var number = regexp.MustCompile(`^:?\d+$`)

func Parse(input string) Result {
	s := strings.TrimSpace(ansi.ReplaceAllString(input, ""))
	if len(s) > 4096 {
		return Result{Error: "주소가 너무 깁니다"}
	}
	for len(s) >= 2 && ((s[0] == s[len(s)-1] && strings.ContainsRune("\"'`", rune(s[0]))) || (s[0] == '<' && s[len(s)-1] == '>')) {
		s = s[1 : len(s)-1]
	}
	candidates := urls.FindAllString(s, -1)
	if len(candidates) == 1 && (strings.HasPrefix(strings.ToLower(s), "http://") || strings.HasPrefix(strings.ToLower(s), "https://")) && !strings.ContainsAny(s, "\r\n") {
		candidates = nil
	}
	if len(candidates) > 1 {
		return Result{Candidates: candidates}
	}
	if len(candidates) == 1 {
		s = candidates[0]
	}
	if number.MatchString(s) {
		s = "localhost:" + strings.TrimPrefix(s, ":")
	}
	if !strings.Contains(s, "://") {
		s = "http://" + s
	}
	u, err := url.Parse(s)
	if err != nil {
		return Result{Error: "주소를 해석할 수 없습니다: " + err.Error()}
	}
	u.Scheme = strings.ToLower(u.Scheme)
	if u.Scheme != "http" && u.Scheme != "https" {
		return Result{Error: "HTTP 또는 HTTPS 주소를 입력해 주세요"}
	}
	if u.User != nil || u.Opaque != "" {
		return Result{Error: "사용자 인증 정보가 포함된 주소는 지원하지 않습니다"}
	}
	host := strings.ToLower(u.Hostname())
	if strings.Contains(host, ":") && !strings.HasPrefix(u.Host, "[") {
		return Result{Error: "IPv6 주소는 [::1]:5173 형식으로 입력해 주세요"}
	}
	if host == "localhost" || host == "0.0.0.0" {
		host = "127.0.0.1"
	} else if host == "::" {
		host = "::1"
	} else {
		ip, e := netip.ParseAddr(host)
		if e != nil || !ip.IsLoopback() || ip.Zone() != "" {
			return Result{Error: "선택한 Mac의 localhost, 127.0.0.1 또는 [::1] 주소를 입력해 주세요"}
		}
		host = ip.String()
	}
	ep := Endpoint{Scheme: u.Scheme, RemoteHost: host, Path: u.Path, RawPath: u.RawPath, Query: u.RawQuery, Fragment: u.Fragment, RawFragment: u.RawFragment}
	if ep.Path == "" {
		ep.Path = "/"
	}
	if u.Port() == "" {
		return Result{Endpoint: ep, NeedsPort: true}
	}
	n, e := strconv.Atoi(u.Port())
	if e != nil || n < 1024 || n > 65535 {
		return Result{Error: fmt.Sprintf("개발 서버 포트는 1024–65535 범위여야 합니다: %s", u.Port())}
	}
	ep.RemotePort = n
	return Result{Endpoint: ep}
}
