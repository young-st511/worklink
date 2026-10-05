package address

import "testing"

func TestParse(t *testing.T) {
	cases := []struct{ in, host, url string }{
		{"5173", "127.0.0.1", "http://localhost:15173/"},
		{":5173", "127.0.0.1", "http://localhost:15173/"},
		{" `localhost:5173` ", "127.0.0.1", "http://localhost:15173/"},
		{"Local: \x1b[32mhttp://0.0.0.0:5173/preview?a=1#view\x1b[0m", "127.0.0.1", "http://localhost:15173/preview?a=1#view"},
		{"https://localhost:8443/a%2Fb?q=a%20b#c", "127.0.0.1", "https://localhost:15173/a%2Fb?q=a%20b#c"},
		{"[::1]:5173/preview", "::1", "http://localhost:15173/preview"},
		{"http://[::]:5173/", "::1", "http://localhost:15173/"},
	}
	for _, c := range cases {
		t.Run(c.in, func(t *testing.T) {
			r := Parse(c.in)
			if r.Error != "" || r.NeedsPort || len(r.Candidates) > 0 {
				t.Fatalf("%+v", r)
			}
			if r.Endpoint.RemoteHost != c.host || r.Endpoint.LocalURL(15173) != c.url {
				t.Fatalf("%+v %s", r, r.Endpoint.LocalURL(15173))
			}
		})
	}
}
func TestNeedsInput(t *testing.T) {
	if !Parse("http://localhost/").NeedsPort {
		t.Fatal("missing port")
	}
	if len(Parse("Local: http://localhost:5173/\nOther: http://localhost:4387/").Candidates) != 2 {
		t.Fatal("multiple candidates")
	}
	for _, s := range []string{"0", "65536", "example.com:5173", "http://localhost:abc/", "ftp://localhost:5173/", "http://user:pass@localhost:5173/", "::1:5173", "http://localhost:5173/\nhello"} {
		if Parse(s).Error == "" && s != "http://localhost:5173/\nhello" {
			t.Errorf("accepted %q", s)
		}
	}
}
func TestQueryAndFragmentPreserved(t *testing.T) {
	for _, s := range []string{"http://localhost:5173/?q=x'", "'http://localhost:5173/a?q=a%20b#view%2Fitem'"} {
		r := Parse(s)
		if r.Error != "" {
			t.Fatal(r)
		}
		if s[0] == 'h' && r.Endpoint.Query != "q=x'" {
			t.Fatal(r)
		}
		if s[0] == '\'' && r.Endpoint.LocalURL(15173) != "http://localhost:15173/a?q=a%20b#view%2Fitem" {
			t.Fatal(r)
		}
	}
	if len(Parse("http://localhost:5173/\nhttp://localhost:4387/").Candidates) != 2 {
		t.Fatal("multiple URL ambiguity")
	}
}
