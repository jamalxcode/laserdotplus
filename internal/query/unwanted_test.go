package query

import "testing"

// The searches Laserdot+'s Clean Up ▸ Probably Unwanted runs (UnwantedModel.rules).
func TestUnwantedQueriesParse(t *testing.T) {
	for _, q := range []string{"kind:video duration:<3s", "kind:video height:<240", "kind:video bitrate:<300kbps", "screenshot:true", "kind:image width:<160 height:<160"} {
		pq, err := Parse(q)
		if err != nil {
			t.Errorf("%s: %v", q, err)
			continue
		}
		if _, err := Compile(pq, false); err != nil {
			t.Errorf("%s: %v", q, err)
		}
	}
}
