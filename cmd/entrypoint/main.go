// Package main implements the entrypoint wrapper for CloudQuery plugin OCI images.
//
// It reads CQ_PLUGIN_ADDRESS and CQ_PLUGIN_PORT environment variables,
// constructs the appropriate --address flag, and execs the /plugin binary.
// This allows Kubernetes deployments to override the listen address/port
// without modifying the container command.
package main

import (
	"fmt"
	"os"
	"syscall"
)

const (
	// pluginBinary is the absolute path to the CloudQuery plugin binary.
	pluginBinary = "/plugin"

	// defaultAddress is the default bind address (all interfaces, IPv4+IPv6).
	defaultAddress = "[::]"

	// defaultPort is the default gRPC server port.
	defaultPort = "7777"

	// envAddress is the environment variable to override the bind address.
	envAddress = "CQ_PLUGIN_ADDRESS"

	// envPort is the environment variable to override the bind port.
	envPort = "CQ_PLUGIN_PORT"
)

func main() {
	addr := getEnvOrDefault(envAddress, defaultAddress)
	port := getEnvOrDefault(envPort, defaultPort)

	// Build the final argument list for the plugin binary.
	// os.Args[0] is this entrypoint binary; os.Args[1:] are the CMD from Dockerfile
	// (e.g., "serve", "--address", "[::]:7777", "--log-format", "json", "--log-level", "info").
	//
	// We need to replace/inject the --address flag with the env-var-derived value.
	args := buildArgs(os.Args[1:], addr, port)

	// Exec replaces this process with /plugin — no child process, clean PID 1 behavior.
	if err := syscall.Exec(pluginBinary, append([]string{pluginBinary}, args...), os.Environ()); err != nil {
		fmt.Fprintf(os.Stderr, "entrypoint: failed to exec %s: %v\n", pluginBinary, err)
		os.Exit(1)
	}
}

// getEnvOrDefault returns the value of the environment variable or the default.
func getEnvOrDefault(key, defaultVal string) string {
	if val, ok := os.LookupEnv(key); ok && val != "" {
		return val
	}
	return defaultVal
}

// buildArgs constructs the argument list for the plugin binary.
// If CQ_PLUGIN_ADDRESS or CQ_PLUGIN_PORT env vars are set, any existing
// --address flag in the args is replaced. Otherwise, the original args are
// passed through unchanged.
func buildArgs(cmdArgs []string, addr, port string) []string {
	addrEnvSet := os.Getenv(envAddress) != "" || os.Getenv(envPort) != ""
	if !addrEnvSet {
		// No env override — pass through CMD args as-is.
		return cmdArgs
	}

	// Build the address value from env vars.
	listenAddr := fmt.Sprintf("%s:%s", addr, port)

	// Replace existing --address in args, or prepend it after the subcommand.
	result := make([]string, 0, len(cmdArgs)+2)
	skipNext := false
	replaced := false

	for i, arg := range cmdArgs {
		if skipNext {
			skipNext = false
			continue
		}
		if arg == "--address" && i+1 < len(cmdArgs) {
			// Replace the existing --address value.
			result = append(result, "--address", listenAddr)
			skipNext = true
			replaced = true
			continue
		}
		result = append(result, arg)
	}

	if !replaced && len(result) > 0 {
		// Insert --address after the subcommand (e.g., "serve").
		sub := result[0]
		rest := result[1:]
		result = append([]string{sub, "--address", listenAddr}, rest...)
	}

	return result
}
