// Package rodiniacore is the gomobile bridge between the Swift tunnel and Xray-core.
//
// The NetworkExtension owns the utun device; Xray's TUN inbound reads and writes it
// through the file descriptor handed over in the xray.tun.fd environment variable.
package rodiniacore

import (
	"errors"
	"os"
	"runtime/debug"
	"strconv"
	"strings"
	"sync"

	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/infra/conf/serial"
	_ "github.com/xtls/xray-core/main/distro/all"
)

var (
	mu       sync.Mutex
	instance *core.Instance
)

// Start launches Xray with a JSON config, reading packets from tunFd.
// A running instance is stopped first, so Start doubles as a reload.
func Start(configJSON string, tunFd int) error {
	mu.Lock()
	defer mu.Unlock()

	if instance != nil {
		instance.Close()
		instance = nil
	}

	// Xray-core plus its gVisor netstack keeps far more than 32 MB of live heap. A
	// memory limit below that leaves the collector permanently over budget: it can
	// never reach its goal, so it re-arms immediately and runs back to back on every
	// processor, pinning cores for as long as the tunnel is up. The old 32 MB ceiling
	// did not hold RSS down either, so it bought nothing. Let the collector pace
	// itself normally instead.
	debug.SetGCPercent(100)

	if err := os.Setenv("xray.tun.fd", strconv.Itoa(tunFd)); err != nil {
		return err
	}

	config, err := serial.LoadJSONConfig(strings.NewReader(configJSON))
	if err != nil {
		return err
	}
	server, err := core.New(config)
	if err != nil {
		return err
	}
	if err := server.Start(); err != nil {
		server.Close()
		return err
	}
	instance = server
	return nil
}

// Stop shuts Xray down. Stopping when nothing runs is not an error.
func Stop() error {
	mu.Lock()
	defer mu.Unlock()

	if instance == nil {
		return nil
	}
	err := instance.Close()
	instance = nil
	debug.FreeOSMemory()
	return err
}

// Running reports whether an instance is up.
func Running() bool {
	mu.Lock()
	defer mu.Unlock()
	return instance != nil
}

// Version is the bundled Xray-core version.
func Version() string {
	return core.Version()
}

// Validate checks a config without starting anything, for friendlier errors in the app.
func Validate(configJSON string) error {
	if strings.TrimSpace(configJSON) == "" {
		return errors.New("empty config")
	}
	_, err := serial.LoadJSONConfig(strings.NewReader(configJSON))
	return err
}
