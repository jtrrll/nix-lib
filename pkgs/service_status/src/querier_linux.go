//go:build linux

package main

import (
	"fmt"
	"os/exec"
	"strings"
)

const defaultPrefix = ""

type SystemdQuerier struct {
	prefix string
}

func newQuerier(prefix string) Querier {
	return &SystemdQuerier{prefix: prefix}
}

func (q *SystemdQuerier) QueryAll() ([]ServiceStatus, error) {
	cmd := exec.Command(
		"systemctl", "--user", "list-units",
		"--type=service,timer",
		"--all",
		"--no-legend",
		"--no-pager",
		"--plain",
	)
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("systemctl list-units: %w", err)
	}

	var units []string
	for _, line := range strings.Split(strings.TrimSpace(string(output)), "\n") {
		fields := strings.Fields(line)
		if len(fields) < 1 {
			continue
		}
		unit := fields[0]
		if q.prefix != "" && !strings.HasPrefix(unit, q.prefix) {
			continue
		}
		// Skip timer units; we extract schedule from the service's associated timer
		if strings.HasSuffix(unit, ".timer") {
			continue
		}
		units = append(units, unit)
	}

	var statuses []ServiceStatus
	for _, unit := range units {
		status := q.queryUnit(unit)
		statuses = append(statuses, status)
	}

	return statuses, nil
}

func (q *SystemdQuerier) queryUnit(unit string) ServiceStatus {
	props := q.getProperties(
		unit,
		"ActiveState", "SubState", "ExecMainStatus",
	)

	name := strings.TrimSuffix(unit, ".service")
	if q.prefix != "" {
		name = strings.TrimPrefix(name, q.prefix)
	}

	status := ServiceStatus{
		Name: name,
	}

	activeState := props["ActiveState"]
	subState := props["SubState"]
	exitStatus := props["ExecMainStatus"]

	switch activeState {
	case "active":
		if subState == "running" {
			status.State = "running"
		} else {
			status.State = "idle"
			status.Detail = "last exit: success"
		}
	case "inactive":
		status.State = "idle"
		if exitStatus != "" && exitStatus != "0" {
			status.State = "error"
			status.Detail = "last exit: " + exitStatus
		} else {
			status.Detail = "last exit: success"
		}
	case "failed":
		status.State = "error"
		status.Detail = "last exit: " + exitStatus
	default:
		status.State = activeState
	}

	// Check for associated timer
	timerUnit := strings.TrimSuffix(unit, ".service") + ".timer"
	timerProps := q.getProperties(timerUnit, "ActiveState", "TimersCalendar")
	if timerProps["ActiveState"] == "active" {
		status.Kind = "scheduled"
		if cal := timerProps["TimersCalendar"]; cal != "" {
			status.Schedule = parseTimersCalendar(cal)
		}
	} else if subState == "running" {
		status.Kind = "daemon"
	} else {
		status.Kind = "oneshot"
	}

	return status
}

func (q *SystemdQuerier) getProperties(unit string, props ...string) map[string]string {
	propArg := "--property=" + strings.Join(props, ",")
	cmd := exec.Command(
		"systemctl", "--user", "show", unit,
		propArg,
		"--no-pager",
	)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return make(map[string]string)
	}

	result := make(map[string]string)
	for _, line := range strings.Split(strings.TrimSpace(string(output)), "\n") {
		parts := strings.SplitN(line, "=", 2)
		if len(parts) == 2 {
			result[parts[0]] = parts[1]
		}
	}
	return result
}

func parseTimersCalendar(raw string) string {
	// TimersCalendar format: "{ OnCalendar=daily ; next_elapse=... }"
	// Extract the OnCalendar value
	if idx := strings.Index(raw, "OnCalendar="); idx >= 0 {
		rest := raw[idx+len("OnCalendar="):]
		if end := strings.IndexAny(rest, " ;}"); end >= 0 {
			return rest[:end]
		}
		return rest
	}
	return raw
}
