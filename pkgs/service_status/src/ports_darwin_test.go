//go:build darwin

package main

import (
	"testing"
)

func TestParseLsofOutput_Deduplicate(t *testing.T) {
	// lsof often reports the same port multiple times for IPv4 and IPv6
	input := `p1234
cmy-service
n127.0.0.1:8080
n[::1]:8080
p5678
cother-service
n127.0.0.1:9090`

	ports := parseLsofOutput(input)

	if len(ports) != 2 {
		t.Fatalf("expected 2 ports, got %d: %+v", len(ports), ports)
	}

	if ports[0].Port != 8080 {
		t.Errorf("expected port 8080, got %d", ports[0].Port)
	}
	if ports[0].Process != "my-service" {
		t.Errorf("expected process my-service, got %q", ports[0].Process)
	}
	if ports[0].PID != "1234" {
		t.Errorf("expected PID 1234, got %q", ports[0].PID)
	}

	if ports[1].Port != 9090 {
		t.Errorf("expected port 9090, got %d", ports[1].Port)
	}
	if ports[1].Process != "other-service" {
		t.Errorf("expected process other-service, got %q", ports[1].Process)
	}
}

func TestParseLsofOutput_MultipleProcessesSamePort(t *testing.T) {
	// Two processes listening on the same port (e.g., after fork)
	// should only appear once
	input := `p1234
cmy-service
n127.0.0.1:8080
p5678
cmy-service
n127.0.0.1:8080`

	ports := parseLsofOutput(input)

	if len(ports) != 1 {
		t.Fatalf("expected 1 port, got %d: %+v", len(ports), ports)
	}

	if ports[0].Port != 8080 {
		t.Errorf("expected port 8080, got %d", ports[0].Port)
	}
	if ports[0].PID != "1234" {
		t.Errorf("expected first PID 1234, got %q", ports[0].PID)
	}
}

func TestParseLsofOutput_Empty(t *testing.T) {
	ports := parseLsofOutput("")
	if len(ports) != 0 {
		t.Fatalf("expected 0 ports, got %d", len(ports))
	}
}
