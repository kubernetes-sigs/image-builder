#!/bin/bash

sed -i '/^preserve_hostname/s/false/true/' /etc/cloud/cloud.cfg
