package install

import (
	"strings"
	"testing"
)

func TestCleanupPlist(t *testing.T) {
	b, err := CleanupPlist("/tmp/work & link/bin", "/tmp/work < data", 4)
	if err != nil {
		t.Fatal(err)
	}
	s := string(b)
	for _, part := range []string{"StartCalendarInterval", "<integer>4</integer>", "work &amp; link", "work &lt; data", "WORKLINK_DATA_DIR", "cleanup"} {
		if !strings.Contains(s, part) {
			t.Fatal(part, s)
		}
	}
	if strings.Contains(s, "KeepAlive") {
		t.Fatal("cleanup must not remain running")
	}
}
