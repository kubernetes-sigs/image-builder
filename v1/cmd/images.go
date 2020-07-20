package cmd

import (
	"fmt"
	"os"
	"text/tabwriter"

	"github.com/flanksource/commons/logger"
	"github.com/spf13/cobra"
	"sigs.k8s.io/image-builder/pkg/distros"
)

var Images = cobra.Command{
	Use:   "images",
	Short: "List all available image/OS combinations",
	Args:  cobra.MinimumNArgs(0),
	Run: func(cmd *cobra.Command, args []string) {

		dists, err := distros.GetDistributions()
		if err != nil {
			logger.Fatalf("Cannot list distros: %v", err)
		}
		w := tabwriter.NewWriter(os.Stdout, 3, 2, 3, ' ', tabwriter.DiscardEmptyColumns)
		fmt.Fprintf(w, "ALIAS\tOS\tDISTRO\tRELEASE\tVERSION\tAMI\tQEMU\tGCE\tAZURE\tDOCKER\tISO\tOVA\n")

		for name, _distro := range dists {
			distro := _distro.GetDistribution()
			fmt.Fprintf(w, "%s\t%s\t", name, distro.OS)
			fmt.Fprintf(w, "%s\t", distro.Distribution)
			fmt.Fprintf(w, "%s\t", distro.DistributionRelease)
			fmt.Fprintf(w, "%s\t", distro.DistributionVersion)
			if distro.AMI != nil {
				fmt.Fprintf(w, "✓\t")
			} else {
				fmt.Fprintf(w, "\t")
			}
			if distro.Qemu != nil {
				fmt.Fprintf(w, "✓\t")
			} else {
				fmt.Fprintf(w, "\t")
			}
			if distro.GCE != nil {
				fmt.Fprintf(w, "✓\t")
			} else {
				fmt.Fprintf(w, "\t")
			}
			if distro.Azure != nil {
				fmt.Fprintf(w, "✓\t")
			} else {
				fmt.Fprintf(w, "\t")
			}
			if distro.Docker != nil {
				fmt.Fprintf(w, "✓\t")
			} else {
				fmt.Fprintf(w, "\t")
			}
			if distro.ISO != nil {
				fmt.Fprintf(w, "✓\t")
			} else {
				fmt.Fprintf(w, "\t")
			}
			if distro.OVA != nil {
				fmt.Fprintf(w, "✓\t")
			} else {
				fmt.Fprintf(w, "\t")
			}
			fmt.Fprint(w, "\n")
		}
		w.Flush()

	},
}

// OS                  string      `yaml:"os,omitempty"`
// AMI                 AMI         `yaml:"ami,omitempty"`
// Qemu                DiskImage   `yaml:"qemu,omitempty"`
// GCE                 GCEImage    `yaml:"gce,omitempty"`
// Azure               AzureImage  `yaml:"azure,omitempty"`
// Docker              DockerImage `yaml:"docker,omitempty"`
// ISO                 ISO         `yaml:"iso,omitempty"`
// OVA                 OVA         `yaml:"ova,omitempty`
// Distribution        string      `yaml:"distribution,omitempty"`
// DistributionRelease string      `yaml:"distribution_release,omitempty"`
// DistributionVersion string      `yaml:"distribution_version,omitempty"`
// Family              string      `yaml:"family,omitempty"`
// SSHUsername         string      `yaml:"ssh_username,omitempty"`
