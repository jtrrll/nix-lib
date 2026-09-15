//go:build darwin

package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

const defaultPrefix = "org.nix-community.home."

type LaunchdQuerier struct {
	prefix string
}

func newQuerier(prefix string) Querier {
	return &LaunchdQuerier{prefix: prefix}
}

type plistData struct {
	Label                 string   `json:"Label"`
	ProgramArguments      []string `json:"ProgramArguments"`
	RunAtLoad             bool     `json:"RunAtLoad"`
	KeepAlive             any      `json:"KeepAlive"`
	StandardOutPath       string   `json:"StandardOutPath"`
	StandardErrorPath     string   `json:"StandardErrorPath"`
	StartCalendarInterval any      `json:"StartCalendarInterval"`
	StartInterval         int      `json:"StartInterval"`
}

type calendarInterval struct {
	Minute  *int `json:"Minute"`
	Hour    *int `json:"Hour"`
	Day     *int `json:"Day"`
	Weekday *int `json:"Weekday"`
	Month   *int `json:"Month"`
}

func (q *LaunchdQuerier) QueryAll() ([]ServiceStatus, error) {
	// Get runtime status from launchctl list
	runtimeStatus := q.getRuntimeStatus()

	// Read plists for metadata
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, fmt.Errorf("getting home dir: %w", err)
	}

	plistDir := filepath.Join(home, "Library", "LaunchAgents")
	entries, err := os.ReadDir(plistDir)
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", plistDir, err)
	}

	var statuses []ServiceStatus
	for _, entry := range entries {
		if !strings.HasPrefix(entry.Name(), q.prefix) || !strings.HasSuffix(entry.Name(), ".plist") {
			continue
		}

		label := strings.TrimSuffix(entry.Name(), ".plist")
		name := strings.TrimPrefix(label, q.prefix)
		plistPath := filepath.Join(plistDir, entry.Name())

		status := ServiceStatus{Name: name}

		if rt, ok := runtimeStatus[label]; ok {
			status.State = rt.State
			status.Detail = rt.Detail
		} else {
			status.State = "not loaded"
		}

		if plist, err := parsePlist(plistPath); err == nil {
			status.Schedule = formatSchedule(plist)
			status.Kind = inferKind(plist)
		}

		statuses = append(statuses, status)
	}

	return statuses, nil
}

type runtimeInfo struct {
	State  string
	Detail string
}

func (q *LaunchdQuerier) getRuntimeStatus() map[string]runtimeInfo {
	result := make(map[string]runtimeInfo)

	cmd := exec.Command("launchctl", "list")
	output, err := cmd.Output()
	if err != nil {
		return result
	}

	for _, line := range strings.Split(strings.TrimSpace(string(output)), "\n")[1:] {
		fields := strings.Fields(line)
		if len(fields) < 3 {
			continue
		}
		label := fields[2]
		if !strings.HasPrefix(label, q.prefix) {
			continue
		}

		pid := fields[0]
		exitStatus := fields[1]

		info := runtimeInfo{}
		if pid != "-" && pid != "0" {
			info.State = "running"
			info.Detail = fmt.Sprintf("pid %s", pid)
		} else if exitStatus == "0" {
			info.State = "idle"
			info.Detail = "last exit: success"
		} else {
			info.State = "error"
			info.Detail = fmt.Sprintf("last exit: %s", exitStatus)
		}

		result[label] = info
	}

	return result
}

func parsePlist(path string) (*plistData, error) {
	cmd := exec.Command("plutil", "-convert", "json", "-o", "-", path)
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("plutil: %w", err)
	}

	var data plistData
	if err := json.Unmarshal(output, &data); err != nil {
		return nil, fmt.Errorf("parsing plist JSON: %w", err)
	}

	return &data, nil
}

func formatSchedule(plist *plistData) string {
	if plist.StartInterval > 0 {
		return fmt.Sprintf("every %ds", plist.StartInterval)
	}

	if plist.StartCalendarInterval == nil {
		if plist.RunAtLoad {
			return "on load"
		}
		return ""
	}

	intervals := parseCalendarIntervals(plist.StartCalendarInterval)
	if len(intervals) == 0 {
		return ""
	}

	var parts []string
	for _, ci := range intervals {
		parts = append(parts, formatCalendarInterval(ci))
	}

	schedule := strings.Join(parts, "; ")
	if plist.RunAtLoad {
		schedule += " + on load"
	}
	return schedule
}

func parseCalendarIntervals(raw any) []calendarInterval {
	data, err := json.Marshal(raw)
	if err != nil {
		return nil
	}

	// Try array first
	var intervals []calendarInterval
	if err := json.Unmarshal(data, &intervals); err == nil {
		return intervals
	}

	// Try single object
	var single calendarInterval
	if err := json.Unmarshal(data, &single); err == nil {
		return []calendarInterval{single}
	}

	return nil
}

var weekdays = []string{"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}

func formatCalendarInterval(ci calendarInterval) string {
	var parts []string

	if ci.Weekday != nil && *ci.Weekday >= 0 && *ci.Weekday < 7 {
		parts = append(parts, weekdays[*ci.Weekday])
	}
	if ci.Month != nil {
		parts = append(parts, fmt.Sprintf("month %d", *ci.Month))
	}
	if ci.Day != nil {
		parts = append(parts, fmt.Sprintf("day %d", *ci.Day))
	}

	hour, minute := 0, 0
	if ci.Hour != nil {
		hour = *ci.Hour
	}
	if ci.Minute != nil {
		minute = *ci.Minute
	}
	if ci.Hour != nil || ci.Minute != nil {
		parts = append(parts, fmt.Sprintf("%02d:%02d", hour, minute))
	}

	if len(parts) == 0 {
		return "daily"
	}
	return strings.Join(parts, " ")
}

func inferKind(plist *plistData) string {
	if plist.StartCalendarInterval != nil || plist.StartInterval > 0 {
		return "scheduled"
	}

	switch ka := plist.KeepAlive.(type) {
	case bool:
		if ka {
			return "daemon"
		}
	case map[string]any:
		if len(ka) > 0 {
			return "daemon"
		}
	}

	if plist.RunAtLoad {
		return "daemon"
	}

	return "oneshot"
}
