//go:build linux

package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
)

func listPorts() ([]PortInfo, error) {
	cmd := exec.Command("ss", "-tlnp")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("ss: %w", err)
	}

	ports := parseSsOutput(string(output))

	// Fill in missing process info from /proc
	for i := range ports {
		if ports[i].Process == "" || ports[i].PID == "" {
			if pid, process := findProcessForPort(ports[i].Port); pid != "" {
				ports[i].PID = pid
				ports[i].Process = process
			}
		}
	}

	return ports, nil
}

func parseSsOutput(output string) []PortInfo {
	seen := make(map[int]bool)
	var ports []PortInfo

	lines := strings.Split(strings.TrimSpace(output), "\n")
	if len(lines) < 2 {
		return ports
	}

	for _, line := range lines[1:] {
		fields := strings.Fields(line)
		if len(fields) < 5 {
			continue
		}

		localAddr := fields[3]
		port, ok := parsePort(localAddr)
		if !ok {
			continue
		}

		if seen[port] {
			continue
		}
		seen[port] = true

		process := parseProcessField(fields[len(fields)-1])

		ports = append(ports, PortInfo{
			Port:    port,
			Process: process,
			PID:     parsePidField(fields[len(fields)-1]),
			Address: localAddr,
		})
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

func parseProcessField(field string) string {
	// Format: users:(("process",pid=123,fd=4))
	start := strings.Index(field, "((\"")
	if start < 0 {
		return ""
	}
	end := strings.Index(field[start+3:], "\"")
	if end < 0 {
		return ""
	}
	return field[start+3 : start+3+end]
}

func parsePidField(field string) string {
	// Format: users:(("process",pid=123,fd=4))
	idx := strings.Index(field, "pid=")
	if idx < 0 {
		return ""
	}
	rest := field[idx+4:]
	end := strings.IndexAny(rest, ",)")
	if end < 0 {
		return rest
	}
	return rest[:end]
}

// findProcessForPort scans /proc/net/tcp(6) to find the inode for a port,
// then walks /proc/<pid>/fd to find which process owns it.
func findProcessForPort(port int) (pid, process string) {
	inode := findInodeForPort(port)
	if inode == "" {
		return "", ""
	}

	entries, err := os.ReadDir("/proc")
	if err != nil {
		return "", ""
	}

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		pidStr := entry.Name()
		if _, err := strconv.Atoi(pidStr); err != nil {
			continue
		}

		if ownsInode(pidStr, inode) {
			name := readProcessName(pidStr)
			return pidStr, name
		}
	}

	return "", ""
}

// findInodeForPort reads /proc/net/tcp and /proc/net/tcp6 looking for
// a LISTEN socket on the given port, returning its inode.
func findInodeForPort(port int) string {
	for _, path := range []string{"/proc/net/tcp", "/proc/net/tcp6"} {
		if inode := findInodeInFile(path, port); inode != "" {
			return inode
		}
	}
	return ""
}

func findInodeInFile(path string, port int) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}

	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	if len(lines) < 2 {
		return ""
	}

	for _, line := range lines[1:] {
		fields := strings.Fields(line)
		if len(fields) < 10 {
			continue
		}

		// State 0A = LISTEN
		if fields[3] != "0A" {
			continue
		}

		// local_address is hex_ip:hex_port
		addrParts := strings.SplitN(fields[1], ":", 2)
		if len(addrParts) != 2 {
			continue
		}

		portHex := addrParts[1]
		p, err := strconv.ParseInt(portHex, 16, 32)
		if err != nil {
			continue
		}

		if int(p) == port {
			return fields[9] // inode field
		}
	}

	return ""
}

// ownsInode checks if /proc/<pid>/fd contains a symlink to socket:[<inode>].
func ownsInode(pid, inode string) bool {
	fdDir := filepath.Join("/proc", pid, "fd")
	entries, err := os.ReadDir(fdDir)
	if err != nil {
		return false
	}

	target := "socket:[" + inode + "]"
	for _, entry := range entries {
		link, err := os.Readlink(filepath.Join(fdDir, entry.Name()))
		if err != nil {
			continue
		}
		if link == target {
			return true
		}
	}
	return false
}

func readProcessName(pid string) string {
	// /proc/<pid>/comm contains the process name (truncated to 15 chars)
	data, err := os.ReadFile(filepath.Join("/proc", pid, "comm"))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}
