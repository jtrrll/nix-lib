//go:build darwin

package main

import (
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

func listPorts() ([]PortInfo, error) {
	cmd := exec.Command("lsof", "-iTCP", "-sTCP:LISTEN", "-nP", "-F", "pcn")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("lsof: %w", err)
	}

	return parseLsofOutput(string(output)), nil
}

func parseLsofOutput(output string) []PortInfo {
	seen := make(map[int]bool)
	var ports []PortInfo
	var pid, process string

	for _, line := range strings.Split(strings.TrimSpace(output), "\n") {
		if len(line) == 0 {
			continue
		}

		switch line[0] {
		case 'p':
			pid = line[1:]
		case 'c':
			process = line[1:]
		case 'n':
			addr := line[1:]
			if port, ok := parsePort(addr); ok {
				if seen[port] {
					continue
				}
				seen[port] = true
				ports = append(ports, PortInfo{
					Port:    port,
					Process: process,
					PID:     pid,
					Address: addr,
				})
			}
		}
	}

	return ports
}

func parsePort(addr string) (int, bool) {
	idx := strings.LastIndex(addr, ":")
	if idx < 0 {
		return 0, false
	}
	port, err := strconv.Atoi(addr[idx+1:])
	if err != nil {
		return 0, false
	}
	return port, true
}
