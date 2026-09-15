//go:build linux

package main

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// queryJournal returns kernel/system warnings-and-above for the selected boot.
//
// The boot argument has already been validated against a fixed allowlist by
// parseBoot, and limit by parseLimit, so the arguments passed to journalctl
// are entirely derived from validated input.
func queryJournal(which boot, limit int) ([]LogEntry, error) {
	args := []string{
		"-k",
		"-p", "warning",
		"-o", "json",
		"--no-pager",
		"-n", strconv.Itoa(limit),
	}
	switch which {
	case bootCurrent:
		args = append(args, "-b", "0")
	case bootPrevious:
		args = append(args, "-b", "-1")
	default:
		return nil, fmt.Errorf("unsupported boot selector: %q", which)
	}

	output, err := exec.Command("journalctl", args...).Output()
	if err != nil {
		return nil, fmt.Errorf("journalctl: %w", err)
	}

	return parseJournalJSON(string(output)), nil
}

// parseJournalJSON parses journalctl's -o json output (one JSON object per
// line) into LogEntry values. Malformed or empty lines are skipped rather
// than failing the whole request.
func parseJournalJSON(output string) []LogEntry {
	var entries []LogEntry

	for _, line := range strings.Split(strings.TrimSpace(output), "\n") {
		if line == "" {
			continue
		}

		fields := decodeJournalFields(line)
		message := fields["MESSAGE"]
		if message == "" {
			continue
		}

		entries = append(entries, LogEntry{
			Time:     formatJournalTime(fields["__REALTIME_TIMESTAMP"]),
			Priority: priorityName(fields["PRIORITY"]),
			Unit:     journalUnit(fields),
			Message:  message,
		})
	}

	return entries
}

// decodeJournalFields extracts string-valued fields from a single journal
// JSON object. journald may encode a field as an array of bytes for
// non-UTF-8 data; such fields are ignored since they are not human-readable.
func decodeJournalFields(line string) map[string]string {
	var raw map[string]any
	if err := json.Unmarshal([]byte(line), &raw); err != nil {
		return nil
	}

	fields := make(map[string]string, len(raw))
	for key, value := range raw {
		if s, ok := value.(string); ok {
			fields[key] = s
		}
	}
	return fields
}

func journalUnit(fields map[string]string) string {
	if unit := fields["_SYSTEMD_UNIT"]; unit != "" {
		return unit
	}
	return fields["SYSLOG_IDENTIFIER"]
}

// formatJournalTime converts a __REALTIME_TIMESTAMP (microseconds since the
// Unix epoch) into a local RFC3339-ish timestamp for display.
func formatJournalTime(micros string) string {
	if micros == "" {
		return ""
	}
	usec, err := strconv.ParseInt(micros, 10, 64)
	if err != nil {
		return ""
	}
	return time.UnixMicro(usec).Local().Format("2006-01-02 15:04:05")
}

// priorityName maps a syslog priority level to a human-readable name.
func priorityName(level string) string {
	switch level {
	case "0":
		return "emerg"
	case "1":
		return "alert"
	case "2":
		return "crit"
	case "3":
		return "err"
	case "4":
		return "warning"
	case "5":
		return "notice"
	case "6":
		return "info"
	case "7":
		return "debug"
	default:
		return level
	}
}
