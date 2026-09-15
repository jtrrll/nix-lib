//go:build darwin

package main

import "testing"

func TestParseLogShowJSON(t *testing.T) {
	output := `{"timestamp":"2026-06-03 13:52:31.123456-0400","messageType":"Error","eventMessage":"kernel panic follows","subsystem":"com.apple.kernel"}
{"timestamp":"2026-06-03 13:52:32.000000-0400","messageType":"Fault","eventMessage":"WindowServer died","processImagePath":"/System/Library/CoreServices/WindowServer"}

{"timestamp":"2026-06-03 13:52:33.000000-0400","messageType":"Error","eventMessage":""}
not-json`

	entries := parseLogShowJSON(output, 100)

	if len(entries) != 2 {
		t.Fatalf("expected 2 entries, got %d: %+v", len(entries), entries)
	}

	if entries[0].Message != "kernel panic follows" {
		t.Errorf("entry 0 message = %q", entries[0].Message)
	}
	if entries[0].Priority != "error" {
		t.Errorf("entry 0 priority = %q, want error", entries[0].Priority)
	}
	if entries[0].Unit != "com.apple.kernel" {
		t.Errorf("entry 0 unit = %q, want com.apple.kernel", entries[0].Unit)
	}
	if entries[0].Time == "" {
		t.Errorf("entry 0 time was empty")
	}

	if entries[1].Unit != "WindowServer" {
		t.Errorf("entry 1 unit = %q, want WindowServer (from processImagePath)", entries[1].Unit)
	}
}

func TestParseLogShowJSONLimit(t *testing.T) {
	output := `{"timestamp":"2026-06-03 13:52:31-0400","messageType":"Error","eventMessage":"one"}
{"timestamp":"2026-06-03 13:52:32-0400","messageType":"Error","eventMessage":"two"}
{"timestamp":"2026-06-03 13:52:33-0400","messageType":"Error","eventMessage":"three"}`

	entries := parseLogShowJSON(output, 2)
	if len(entries) != 2 {
		t.Fatalf("limit not honored: got %d entries, want 2", len(entries))
	}
}

func TestParseBoottimeSeconds(t *testing.T) {
	sec, ok := parseBoottimeSeconds("{ sec = 1780509151, usec = 836572 } Wed Jun  3 13:52:31 2026\n")
	if !ok {
		t.Fatal("expected to parse boottime")
	}
	if sec != 1780509151 {
		t.Errorf("sec = %d, want 1780509151", sec)
	}

	if _, ok := parseBoottimeSeconds("garbage"); ok {
		t.Error("expected failure on garbage input")
	}
}
