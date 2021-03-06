package main

import (
	"os"

	"github.com/provenance-io/provenance/cmd/provenanced/cmd"
)

func main() {
	rootCmd, _ := cmd.NewRootCmd()
	if err := cmd.Execute(rootCmd); err != nil {
		os.Exit(1)
	}
}
