apt update
apt -y install gawk bzip2
curl -fsSLO --retry-delay 1 --retry 60 --retry-connrefused --retry-max-time 60 --connect-timeout 20 https://raw.githubusercontent.com/flatcar/init/flatcar-master/bin/flatcar-install
chmod +x flatcar-install
cat <<EOF > ignition.json
{
  "ignition": { "version": "3.0.0" },
  "passwd": {
    "users": [
      {
        "name": "root",
        "sshAuthorizedKeys": [
          "$(cat /root/.ssh/authorized_keys)"
        ]
      }
    ]
  }
}
EOF
./flatcar-install -v -d /dev/sda -i ignition.json -V $FLATCAR_VERSION -C $FLATCAR_CHANNEL # optional: you may provide a Ignition Config as file, it should contain your SSH key
reboot
