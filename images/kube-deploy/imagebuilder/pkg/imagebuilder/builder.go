package imagebuilder

import (
	"bytes"
	"fmt"
	"math/rand"
	"os"
	"path"

	"sigs.k8s.io/image-builder/images/kube-deploy/imagebuilder/pkg/imagebuilder/executor"
)

type Builder struct {
	config *Config
	target *executor.Target
}

func NewBuilder(config *Config, target *executor.Target) *Builder {
	return &Builder{
		config: config,
		target: target,
	}
}

func (b *Builder) RunSetupCommands() error {
	for _, c := range b.config.SetupCommands {
		if err := b.target.Exec(c...); err != nil {
			return err
		}
	}

	return nil
}

func (b *Builder) BuildImage(template []byte, extraEnv map[string]string, logdir string) error {
	tmpdir := fmt.Sprintf("/tmp/imagebuilder-%d", rand.Int63())
	err := b.target.Mkdir(tmpdir, 0755)
	if err != nil {
		return err
	}
	defer b.target.Exec("rm", "-rf", tmpdir)

	if logdir == "" {
		logdir = path.Join(tmpdir, "logs")
	}
	err = b.target.Mkdir(logdir, 0755)
	if err != nil && !os.IsExist(err) {
		return err
	}

	//err = ssh.Exec("git clone https://github.com/andsens/bootstrap-vz.git " + tmpdir + "/bootstrap-vz")
	err = b.target.Exec("git", "clone", b.config.BootstrapVZRepo, "-b", b.config.BootstrapVZBranch, tmpdir+"/bootstrap-vz")
	if err != nil {
		return err
	}

	err = b.target.Put(tmpdir+"/template.yml", len(template), bytes.NewReader(template), 0644)
	if err != nil {
		return err
	}

	cmd := b.target.Command("./bootstrap-vz/bootstrap-vz", "--debug", "--log", logdir, "./template.yml")
	cmd.Cwd = tmpdir
	for k, v := range extraEnv {
		cmd.Env[k] = v
	}
	cmd.Sudo = true
	err = cmd.Run()
	if err != nil {
		return err
	}

	return nil
}
