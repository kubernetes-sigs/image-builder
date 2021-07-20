package main

import (
	"flag"
	"log"
	"net/http"
	"os"
	"strconv"
	"path/filepath"
	"fmt"
	"strings"
)

var (
	dir     = flag.String("b", "", "base directory where kubelet, kube-proxy, containerd, and other binaries live")
	port    = flag.String("p", "8080", "port to serve files on")
	verbose = flag.Bool("v", false, "verbose logging")
	ip = flag.String("ip", "127.0.0.1", "ip address to print for url default")
)

// This will be printed out as a YAML file that can serve as the input to the image
// builder process...

func main() {
	artifacts := map[string]string {
	   "kubelet.exe": "kubernetes_base_url",
	   //"kubernetes_base_url": "https://dl.k8s.io/release/v1.19.2/bin/windows/amd64",
	   "CloudbaseInit*": "cloudbase_init_url",  
	   // "cloudbase_init_url": "https://github.com/cloudbase/cloudbase-init/releases/download/1.1.2/CloudbaseInitSetup_1_1_2_x64.msi",
	   "wins.exe": "wins_url", //: "https://github.com/rancher/wins/releases/download/v0.0.4/wins.exe",
	   "nssm.exe": "nssm_url",
	   // "nssm_url": "https://azurek8scishared.blob.core.windows.net/nssm/nssm.exe",
	   //"additional_debug_files": "https://raw.githubusercontent.com/kubernetes-sigs/sig-windows-tools/master/hack/DebugWindowsNode.ps1",
	}

	flag.Parse()

	if _, err := strconv.Atoi(*port); err != nil {
		log.Fatal("port provided must be a valid integer")
	}

	curr, err := os.Getwd()
	if err != nil {
		log.Fatal("os.Getwd(): ", err)
	}

	if len(*dir) > 0 {
		if _, err := os.Stat(*dir); err != nil {
			log.Fatal("failed to detect dir, err: ", err)
		}
		curr = *dir
	}

	fs := http.FileServer(http.Dir(curr))

	http.Handle("/", http.StripPrefix("/", LoggerHandler{fs}))
	addr := ":" + *port

	// print out the relative path of each artifact so that we can make the right kind of
	// input example.vars file... TODO print these as JSON...
	for name,artifact := range artifacts {
		path := findFile("./", name)
		// this stuff can be copied out as a yaml input to image builder...
		fmt.Println(fmt.Sprintf("%v: http://%v:8080/%v", artifact, *ip, path))
	}

	log.Println("Listening on", addr)

	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatal("ListenAndServe: ", err)
	}
}


func findFile(targetDir string, artifact string) string {
	result := "**none**"
	err := filepath.Walk(targetDir,
    func(path string, info os.FileInfo, err error) error {
    if err != nil {
        return err
    }
	if strings.Contains(path, artifact) {
		result = filepath.Dir(path)
	}
	return nil
	})
	if err != nil {
		log.Println(err)
	}
	return result
}

type LoggerHandler struct {
	fs http.Handler
}

func (l LoggerHandler) ServeHTTP(resp http.ResponseWriter, req *http.Request) {
	args := []interface{}{req.Method, req.RequestURI}
	if *verbose {
		args = append(args, req.RemoteAddr)
	}

	log.Println(args...)
	l.fs.ServeHTTP(resp, req)
}
