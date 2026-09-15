package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"slices"
	"strconv"
	"strings"

	"github.com/urfave/cli/v3"
)

type ServiceStatus struct {
	Name     string `json:"name"`
	State    string `json:"state"`
	Detail   string `json:"detail,omitempty"`
	Schedule string `json:"schedule,omitempty"`
	Kind     string `json:"kind,omitempty"`
}

type PortInfo struct {
	Port    int    `json:"port"`
	Process string `json:"process"`
	PID     string `json:"pid"`
	Address string `json:"address"`
}

// LogEntry is a single kernel/system log line rendered by the dashboard.
type LogEntry struct {
	Time     string `json:"time"`
	Priority string `json:"priority,omitempty"`
	Unit     string `json:"unit,omitempty"`
	Message  string `json:"message"`
}

// boot selects which boot's logs to return. The value is validated against
// this fixed allowlist before use so no caller-controlled string is ever
// passed to the underlying log command.
type boot string

const (
	bootCurrent  boot = "current"
	bootPrevious boot = "previous"
)

func parseBoot(raw string) (boot, bool) {
	switch boot(raw) {
	case bootCurrent:
		return bootCurrent, true
	case bootPrevious:
		return bootPrevious, true
	case "":
		return bootCurrent, true
	default:
		return "", false
	}
}

const (
	// defaultJournalLimit is used when no limit query param is supplied.
	defaultJournalLimit = 100
	// maxJournalLimit bounds how many entries a single request may fetch,
	// protecting against an unbounded journalctl/log invocation.
	maxJournalLimit = 1000
)

// parseLimit interprets the ?limit query param for the journal endpoint.
// An empty value falls back to defaultJournalLimit. Values are clamped to
// maxJournalLimit. A non-numeric or non-positive value is rejected.
func parseLimit(raw string) (int, bool) {
	if raw == "" {
		return defaultJournalLimit, true
	}
	n, err := strconv.Atoi(raw)
	if err != nil || n <= 0 {
		return 0, false
	}
	return min(n, maxJournalLimit), true
}

var version = "dev"

func main() {
	cmd := &cli.Command{
		Name:    "service-status",
		Usage:   "Serves managed background service status over HTTP",
		Version: version,
		Flags: []cli.Flag{
			&cli.IntFlag{
				Name:  "port",
				Usage: "HTTP listen port",
				Value: 5679,
			},
			&cli.StringFlag{
				Name:  "prefix",
				Usage: "Service label prefix to filter by",
				Value: defaultPrefix,
			},
		},
		Action: func(ctx context.Context, cmd *cli.Command) error {
			port := cmd.Int("port")
			prefix := cmd.String("prefix")

			querier := newQuerier(prefix)

			http.HandleFunc("/status", statusHandler(querier))
			http.HandleFunc("/ports", portsHandler())
			http.HandleFunc("/journal", journalHandler())

			addr := fmt.Sprintf("127.0.0.1:%d", port)
			log.Printf("listening on %s (prefix=%q)", addr, prefix)
			return http.ListenAndServe(addr, nil)
		},
	}

	if err := cmd.Run(context.Background(), os.Args); err != nil {
		log.Fatal(err)
	}
}

func statusHandler(querier Querier) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		statuses, err := querier.QueryAll()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		slices.SortFunc(statuses, func(a, b ServiceStatus) int {
			return strings.Compare(a.Name, b.Name)
		})

		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(statuses); err != nil {
			log.Printf("failed to encode response: %v", err)
		}
	}
}

func portsHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ports, err := listPorts()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		slices.SortFunc(ports, func(a, b PortInfo) int {
			return a.Port - b.Port
		})

		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(ports); err != nil {
			log.Printf("failed to encode response: %v", err)
		}
	}
}

func journalHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		which, ok := parseBoot(r.URL.Query().Get("boot"))
		if !ok {
			http.Error(w, "boot must be \"current\" or \"previous\"", http.StatusBadRequest)
			return
		}

		limit, ok := parseLimit(r.URL.Query().Get("limit"))
		if !ok {
			http.Error(w, "limit must be a positive integer", http.StatusBadRequest)
			return
		}

		entries, err := queryJournal(which, limit)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(entries); err != nil {
			log.Printf("failed to encode response: %v", err)
		}
	}
}
