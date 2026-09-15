//go:build linux

package main

import "testing"

func TestParseJournalJSON(t *testing.T) {
	output := `{"__REALTIME_TIMESTAMP":"1780509151000000","PRIORITY":"3","_SYSTEMD_UNIT":"gdm.service","MESSAGE":"amdgpu: ring gfx timeout"}
{"__REALTIME_TIMESTAMP":"1780509152000000","PRIORITY":"4","SYSLOG_IDENTIFIER":"kernel","MESSAGE":"GPU reset begin!"}

{"__REALTIME_TIMESTAMP":"1780509153000000","PRIORITY":"6","MESSAGE":""}
not-json`

	entries := parseJournalJSON(output)

	if len(entries) != 2 {
		t.Fatalf("expected 2 entries, got %d: %+v", len(entries), entries)
	}

	if entries[0].Message != "amdgpu: ring gfx timeout" {
		t.Errorf("entry 0 message = %q", entries[0].Message)
	}
	if entries[0].Priority != "err" {
		t.Errorf("entry 0 priority = %q, want err", entries[0].Priority)
	}
	if entries[0].Unit != "gdm.service" {
		t.Errorf("entry 0 unit = %q, want gdm.service", entries[0].Unit)
	}
	if entries[0].Time == "" {
		t.Errorf("entry 0 time was empty")
	}

	if entries[1].Unit != "kernel" {
		t.Errorf("entry 1 unit = %q, want kernel (from SYSLOG_IDENTIFIER)", entries[1].Unit)
	}
	if entries[1].Priority != "warning" {
		t.Errorf("entry 1 priority = %q, want warning", entries[1].Priority)
	}
}

func TestPriorityName(t *testing.T) {
	cases := map[string]string{
		"0":       "emerg",
		"3":       "err",
		"4":       "warning",
		"6":       "info",
		"unknown": "unknown",
	}
	for level, want := range cases {
		if got := priorityName(level); got != want {
			t.Errorf("priorityName(%q) = %q, want %q", level, got, want)
		}
	}
}

func TestFormatJournalTime(t *testing.T) {
	if got := formatJournalTime(""); got != "" {
		t.Errorf("empty timestamp = %q, want empty", got)
	}
	if got := formatJournalTime("not-a-number"); got != "" {
		t.Errorf("invalid timestamp = %q, want empty", got)
	}
	if got := formatJournalTime("1780509151000000"); got == "" {
		t.Errorf("valid timestamp produced empty output")
	}
}
