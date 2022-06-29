#!/bin/bash

wget https://raw.githubusercontent.com/GoogleCloudPlatform/compute-gpu-installation/main/linux/install_gpu_driver.py -O install_gpu_driver.py

sudo python3 install_gpu_driver.py
