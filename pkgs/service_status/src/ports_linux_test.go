//go:build linux

package main

import (
	"testing"
)

func TestParseSsOutput_Deduplicate(t *testing.T) {
	// ss shows separate lines for IPv4 and IPv6 on the same port
	input := `State      Recv-Q Send-Q Local Address:Port  Peer Address:Port Process
LISTEN     0      128    0.0.0.0:8080       0.0.0.0:*     users:(("my-service",pid=1234,fd=4))
LISTEN     0      128    [::]:8080          [::]:*        users:(("my-service",pid=1234,fd=5))
LISTEN     0      128    127.0.0.1:9090     0.0.0.0:*     users:(("other-svc",pid=5678,fd=3))`

	ports := parseSsOutput(input)

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
	if ports[1].Process != "other-svc" {
		t.Errorf("expected process other-svc, got %q", ports[1].Process)
	}
}

func TestParseSsOutput_NoProcInfo(t *testing.T) {
	// When ss is run without privileges, process info is missing
	input := `State      Recv-Q Send-Q Local Address:Port  Peer Address:Port Process
LISTEN     0      128    0.0.0.0:8080       0.0.0.0:*
LISTEN     0      128    127.0.0.1:9090     0.0.0.0:*`

	ports := parseSsOutput(input)

	if len(ports) != 2 {
		t.Fatalf("expected 2 ports, got %d: %+v", len(ports), ports)
	}

	if ports[0].Port != 8080 {
		t.Errorf("expected port 8080, got %d", ports[0].Port)
	}
	if ports[0].Process != "" {
		t.Errorf("expected empty process, got %q", ports[0].Process)
	}
	if ports[0].PID != "" {
		t.Errorf("expected empty PID, got %q", ports[0].PID)
	}
}

func TestParseSsOutput_DuplicateWithoutProc(t *testing.T) {
	// Duplicate ports without process info should still deduplicate
	input := `State      Recv-Q Send-Q Local Address:Port  Peer Address:Port Process
LISTEN     0      128    0.0.0.0:8080       0.0.0.0:*
LISTEN     0      128    [::]:8080          [::]:*`

	ports := parseSsOutput(input)

	if len(ports) != 1 {
		t.Fatalf("expected 1 port, got %d: %+v", len(ports), ports)
	}

	if ports[0].Port != 8080 {
		t.Errorf("expected port 8080, got %d", ports[0].Port)
	}
}

func TestParseSsOutput_Empty(t *testing.T) {
	ports := parseSsOutput("")
	if len(ports) != 0 {
		t.Fatalf("expected 0 ports, got %d", len(ports))
	}
}

func TestParseSsOutput_HeaderOnly(t *testing.T) {
	input := `State      Recv-Q Send-Q Local Address:Port  Peer Address:Port Process`
	ports := parseSsOutput(input)
	if len(ports) != 0 {
		t.Fatalf("expected 0 ports, got %d", len(ports))
	}
}
