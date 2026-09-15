package main

import "testing"

func TestParseBoot(t *testing.T) {
	cases := []struct {
		raw   string
		want  boot
		valid bool
	}{
		{"current", bootCurrent, true},
		{"previous", bootPrevious, true},
		{"", bootCurrent, true},
		{"CURRENT", "", false},
		{"-1", "", false},
		{"; rm -rf /", "", false},
		{"0 --output=cat", "", false},
	}

	for _, tc := range cases {
		got, ok := parseBoot(tc.raw)
		if ok != tc.valid {
			t.Errorf("parseBoot(%q) valid = %v, want %v", tc.raw, ok, tc.valid)
			continue
		}
		if ok && got != tc.want {
			t.Errorf("parseBoot(%q) = %q, want %q", tc.raw, got, tc.want)
		}
	}
}

func TestParseLimit(t *testing.T) {
	cases := []struct {
		raw   string
		want  int
		valid bool
	}{
		{"", defaultJournalLimit, true},
		{"25", 25, true},
		{"1", 1, true},
		{"999999", maxJournalLimit, true},
		{"0", 0, false},
		{"-5", 0, false},
		{"abc", 0, false},
		{"10; rm -rf /", 0, false},
	}

	for _, tc := range cases {
		got, ok := parseLimit(tc.raw)
		if ok != tc.valid {
			t.Errorf("parseLimit(%q) valid = %v, want %v", tc.raw, ok, tc.valid)
			continue
		}
		if ok && got != tc.want {
			t.Errorf("parseLimit(%q) = %d, want %d", tc.raw, got, tc.want)
		}
	}
}
