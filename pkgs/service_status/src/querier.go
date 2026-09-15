package main

// Querier discovers and queries managed service status.
type Querier interface {
	QueryAll() ([]ServiceStatus, error)
}
