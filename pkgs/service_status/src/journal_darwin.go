//go:build darwin

package main

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// previousBootWindow bounds how far before the last boot the "previous boot"
// view reaches. macOS unified logging has no boot index, so the pre-boot
// window is a time-based approximation of "the logs from before this boot".
const previousBootWindow = 30 * time.Minute

// queryJournal returns system errors and faults for the selected boot using
// the macOS unified logging store.
//
// Unlike Linux journald, macOS has no notion of a discrete "previous boot".
// "current" is approximated as everything since the kernel boot time, and
// "previous" as a bounded window ending at that boot time. macOS `log show`
// has no result-count flag, so the limit is applied while parsing.
func queryJournal(which boot, limit int) ([]LogEntry, error) {
	bootTime, err := lastBootTime()
	if err != nil {
		return nil, err
	}

	args := []string{
		"show",
		"--style", "ndjson",
		"--predicate", `messageType == "Error" OR messageType == "Fault"`,
	}
	switch which {
	case bootCurrent:
		args = append(args, "--start", bootTime.Format("2006-01-02 15:04:05"))
	case bootPrevious:
		args = append(
			args,
			"--start", bootTime.Add(-previousBootWindow).Format("2006-01-02 15:04:05"),
			"--end", bootTime.Format("2006-01-02 15:04:05"),
		)
	default:
		return nil, fmt.Errorf("unsupported boot selector: %q", which)
	}

	output, err := exec.Command("log", args...).Output()
	if err != nil {
		return nil, fmt.Errorf("log show: %w", err)
	}

	return parseLogShowJSON(string(output), limit), nil
}

// lastBootTime reads the kernel boot time from sysctl.
func lastBootTime() (time.Time, error) {
	output, err := exec.Command("sysctl", "-n", "kern.boottime").Output()
	if err != nil {
		return time.Time{}, fmt.Errorf("sysctl kern.boottime: %w", err)
	}
	sec, ok := parseBoottimeSeconds(string(output))
	if !ok {
		return time.Time{}, fmt.Errorf("unparseable kern.boottime: %q", strings.TrimSpace(string(output)))
	}
	return time.Unix(sec, 0).Local(), nil
}

// parseBoottimeSeconds extracts the "sec = N" value from sysctl's
// kern.boottime output, e.g. "{ sec = 1780509151, usec = 836572 } ...".
func parseBoottimeSeconds(output string) (int64, bool) {
	idx := strings.Index(output, "sec = ")
	if idx < 0 {
		return 0, false
	}
	rest := output[idx+len("sec = "):]
	end := strings.IndexAny(rest, ",} ")
	if end < 0 {
		return 0, false
	}
	var sec int64
	if _, err := fmt.Sscanf(rest[:end], "%d", &sec); err != nil {
		return 0, false
	}
	return sec, true
}

type logShowEntry struct {
	Timestamp        string `json:"timestamp"`
	MessageType      string `json:"messageType"`
	EventMessage     string `json:"eventMessage"`
	Subsystem        string `json:"subsystem"`
	ProcessImagePath string `json:"processImagePath"`
}

// parseLogShowJSON parses `log show --style ndjson` output (one JSON object
// per line) into LogEntry values, keeping at most limit entries. Malformed
// or message-less lines are skipped.
func parseLogShowJSON(output string, limit int) []LogEntry {
	var entries []LogEntry

	for _, line := range strings.Split(strings.TrimSpace(output), "\n") {
		if line == "" {
			continue
		}

		var raw logShowEntry
		if err := json.Unmarshal([]byte(line), &raw); err != nil {
			continue
		}
		if raw.EventMessage == "" {
			continue
		}

		entries = append(entries, LogEntry{
			Time:     formatLogShowTime(raw.Timestamp),
			Priority: strings.ToLower(raw.MessageType),
			Unit:     logShowUnit(raw),
			Message:  raw.EventMessage,
		})

		if len(entries) >= limit {
			break
		}
	}

	return entries
}

func logShowUnit(raw logShowEntry) string {
	if raw.Subsystem != "" {
		return raw.Subsystem
	}
	return filepath.Base(raw.ProcessImagePath)
}

// formatLogShowTime reduces log show's timestamp
// ("2026-06-03 13:52:31.123456-0400") to a stable display form.
func formatLogShowTime(ts string) string {
	if ts == "" {
		return ""
	}
	for _, layout := range []string{
		"2006-01-02 15:04:05.000000-0700",
		"2006-01-02 15:04:05-0700",
	} {
		if t, err := time.Parse(layout, ts); err == nil {
			return t.Local().Format("2006-01-02 15:04:05")
		}
	}
	return ts
}
