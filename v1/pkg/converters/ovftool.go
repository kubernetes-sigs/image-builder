package converters

import (
	"fmt"
	"io/ioutil"
	"os"
	"path"

	"github.com/flanksource/commons/files"
	"github.com/flanksource/commons/logger"
	"sigs.k8s.io/image-builder/api"
	"sigs.k8s.io/image-builder/pkg"
)

func OVAToVM(ctx *pkg.BuildContext, from api.Image, to api.Image) (api.Image, error) {
	ova := from.(api.OVA)
	vm := to.(api.VM)
	tmp, _ := ioutil.TempFile("", "options*.json")
	tmp.WriteString(getOptions(vm.Network))
	if !logger.IsTraceEnabled() {
		defer os.Remove(tmp.Name())
	}
	err := ctx.GetBinary("govc")("import.ova --name %s --options %s %s", vm.Name, tmp.Name(), ova.URL)
	return vm, err
}

func VmdkToOVA(ctx *pkg.BuildContext, from api.Image, to api.Image) (api.Image, error) {
	vmdk := from.(api.VMDK)
	ova := to.(api.OVA)
	dir := path.Dir(vmdk.URL)
	name := files.GetBaseName(vmdk.URL)
	ova.URL = path.Join(dir, name+".ova")
	vmx := path.Join(dir, name+".vmx")
	if err := ioutil.WriteFile(vmx, []byte(getVmx(name, vmdk.URL, ova.Properties)), 0644); err != nil {
		return nil, err
	}
	if !logger.IsTraceEnabled() {
		defer os.Remove(vmx)
	}
	if err := ctx.GetBinary("ovftool")("%s %s", vmx, ova.URL); err != nil {
		return nil, err
	}

	return ova, nil
}

func getVmx(name, image string, properties map[string]string) string {
	vmx := fmt.Sprintf(base, name, image)
	for k, v := range properties {
		vmx += fmt.Sprintf("%s=%s\n", k, v)
	}
	logger.Tracef(vmx)
	return vmx
}

func getOptions(network string) string {
	return fmt.Sprintf(options, network)
}

var (
	options = `
	{
    "DiskProvisioning": "thin",
    "IPAllocationPolicy": "dhcpPolicy",
    "IPProtocol": "IPv4",
    "NetworkMapping": [
        {
            "Name": "VM Network",
            "Network": "%s"
        }
    ],
    "MarkAsTemplate": false,
    "PowerOn": false,
    "InjectOvfEnv": false,
    "WaitForIP": false,
    "Name": null
}
`
	base = `
.encoding = "UTF-8"
displayName = "%s"
disk.enableUUID = 1
cleanShutdown = "TRUE"
config.version = "8"
cpuid.coresPerSocket = "2"
ethernet0.addressType = "generated"
ethernet0.generatedAddressOffset = "0"
ethernet0.networkName = "VM Network"
ethernet0.connectionType = "bridged"
ethernet0.pciSlotNumber = "160"
ethernet0.present = "TRUE"
ethernet0.uptCompatibility = "TRUE"
ethernet0.virtualDev = "vmxnet3"
ethernet0.wakeOnPcktRcv = "FALSE"

floppy0.autodetect = "TRUE"
floppy0.startConnected = "FALSE"

guestOS = "other3xlinux-64"
hpet0.present = "TRUE"
ide1:0.autodetect = "TRUE"
ide1:0.clientDevice = "FALSE"
ide1:0.deviceType = "atapi-cdrom"
ide1:0.present = "TRUE"
ide1:0.startConnected = "FALSE"
memSize = "2048"
numvcpus = "2"
pciBridge0.present = "TRUE"
pciBridge4.functions = "8"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"

serial0.present = "TRUE"
serial0.fileType = "file"
serial0.autodetect = "TRUE"
serial0.fileName = "serial.out"
answer.msg.serial.file.open = "Replace"
answer.msg.uuid.altered = "I copied it"

scsi0:0.allowguestconnectioncontrol = "false"
scsi0:0.deviceType = "disk"
scsi0:0.fileName = "%s"
scsi0:0.mode = "persistent"
scsi0:0.present = "TRUE"
scsi0.present = "TRUE"
scsi0.virtualDev = "lsilogic"
svga.present = "TRUE"
svga.vramSize = "134217728"
tools.syncTime = "FALSE"
toolScripts.afterPowerOn = "TRUE"
toolScripts.afterResume = "TRUE"
toolScripts.beforePowerOff = "TRUE"
toolScripts.beforeSuspend = "TRUE"
virtualHW.productCompatibility = "hosted"
virtualhw.version = "11"
vmci0.present = "TRUE"
vmci0.unrestricted = "false"
`
)
