/*
Copyright 2019 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package main

import (
	"fmt"
	"os"

	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"github.com/spf13/cobra/doc"

	"sigs.k8s.io/image-builder/cmd"
)

// version variables are updated by GoReleaser at compile time
var (
	version = "dev"
	commit  = "none"
	date    = "unknown"
)

func main() {
	var root = &cobra.Command{
		Use: "image-builder",
		PersistentPreRun: func(cmd *cobra.Command, args []string) {
			level, _ := cmd.Flags().GetCount("loglevel")
			switch {
			case level > 1:
				log.SetLevel(log.TraceLevel)
			case level > 0:
				log.SetLevel(log.DebugLevel)
			default:
				log.SetLevel(log.InfoLevel)
			}
		},
	}

	root.AddCommand(&cmd.Build, &cmd.Images)

	root.AddCommand(&cobra.Command{
		Use:   "version",
		Short: "Print the version of image-builder",
		Args:  cobra.MinimumNArgs(0),
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Println(version)
		},
	})

	root.AddCommand(&cobra.Command{
		Use:   "docs",
		Short: "generate documentation",
		Run: func(cmd *cobra.Command, args []string) {
			err := doc.GenMarkdownTree(root, "docs")
			if err != nil {
				log.Fatal(err)
			}
			fmt.Println("Documentation generated at: docs")
		},
	})
	root.PersistentFlags().CountP("loglevel", "v", "Increase logging level")

	root.PersistentFlags().Bool("dry-run", false, "Dont execute packer")
	root.PersistentFlags().StringP("name", "n", "", "Template name")

	if err := root.Execute(); err != nil {
		os.Exit(1)
	}
}
