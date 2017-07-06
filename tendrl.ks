#version=DEVEL
# Install OS instead of upgrade
install
# Root password
rootpw redhat
# Run the Setup Agent on first boot
firstboot --reconfig
# System keyboard
keyboard us
# System language
lang en_US
# SELinux configuration
selinux --disabled
services --enabled salt-master, mongod, skyringd
# Do not configure the X Window System
skipx
# Installation logging level
logging --level=info
# Reboot after installation
reboot
# System timezone
timezone --isUtc America/New_York
# Network information
network  --bootproto=dhcp --device=eth0 --onboot=on
# Firewall configuration
firewall --disable
# System bootloader configuration
bootloader --location=mbr
# Clear the Master Boot Record
zerombr
# Partition clearing information
clearpart --all --initlabel
# Disk partitioning information
part swap --asprimary --fstype="swap" --size=2048
part / --asprimary --fstype="ext4" --grow --size=2000

%packages
@core
@base
tendrl-commons
tendrl-node-agent
tendrl-api
tendrl-dashboard
tendrl-node-monitoring
tendrl-performance-monitoring
tendrl-alerting
etcd
openssh
openssh-clients
openssh-server
vim-enhanced
yum-utils
screen
strace
ntp
nfs-utils
make
%end

%post
configureEtcd() {
cat > /etc/tendrl/etcd.yml <<EOF
---
:development:
  :base_key: ''
  :host: '127.0.0.1'
  :port: 2379
  :user_name: 'username'
  :password: 'password'
:test:
  :base_key: ''
  :host: '127.0.0.1'
  :port: 2379
  :user_name: 'username'
  :password: 'password'
:production:
  :base_key: ''
  :host: '${APISERVER}'
  :port: 2379
  :user_name: ''
  :password: ''
EOF
}

gethostip() {
    local _ip _myip _line _nl=$'\n'
    while IFS=$': \t' read -a _line ;do
        [ -z "${_line%inet}" ] &&
           _ip=${_line[${#_line[1]}>4?1:2]} &&
           [ "${_ip#127.0.0.1}" ] && _myip=$_ip
      done< <(LANG=C /sbin/ip addr)
    printf ${1+-v} $1 "%s${_nl:0:$[${#1}>0?0:1]}" $_myip | cut -f1  -d'/'
}

/usr/bin/yum update -y --skip-broken
cat > /etc/sysconfig/network-scripts/ifcfg-eth0 << EOF
DEVICE="eth0"
BOOTPROTO="dhcp"
ONBOOT="yes"
TYPE="Ethernet"
EOF

sleep 10

APISERVER=`gethostip`
configureEtcd

/usr/lib/python2.7/site-packages/graphite/manage.py syncdb --noinput
chown apache:apache /var/lib/graphite-web/graphite.db
/sbin/service carbon-cache start
/sbin/chkconfig carbon-cache on
/sbin/service httpd start
/sbin/chkconfig httpd on

cat > /etc/cron.d/tendrl << EOF
* * * * * /usr/bin/sh /usr/local/setup-script
EOF

cat > /usr/local/mongo-init-script << EOF
#!/bin/bash
sed -i /etc/etcd/etcd.conf
  -e "s/^#ETCD_LISTEN_CLIENT_URLS=.*/ETCD_LISTEN_CLIENT_URLS=$(APISERVER)/"
sed -i /etc/tendrl/node-agent/node-agent.conf.yaml
  -e "s/^etcd_connection =.*/etcd_connection =$(APISERVER)/"
sed -i /etc/tendrl/node-monitoring/node-monitoring.conf.yaml
  -e "s/^etcd_connection =.*/etcd_connection =$(APISERVER)/"
sed -i /etc/tendrl/performance-monitoring/performance-monitoring.conf.yaml
  -e "s/^etcd_connection =.*/etcd_connection = $(APISERVER)/"
sed -i /etc/tendrl/performance-monitoring/performance-monitoring.conf.yaml
  -e "s/^time_series_db_server =.*/time_series_db_server = $(APISERVER)/"
sed -i /etc/tendrl/performance-monitoring/performance-monitoring.conf.yaml
  -e "s/^api_server_addr =.*/api_server_addr = $(APISERVER)/"
sed -i /etc/tendrl/alerting/alerting.conf.yaml
   -e "s/^etcd_connection =.*/etcd_connection =$(APISERVER)/"

/bin/systemctl enable etcd
/sbin/service etcd start

/bin/systemctl enable tendrl-node-agent
/sbin/service tendrl-node-agent start

cd /usr/share/tendrl-api;\
RACK_ENV=production rake etcd:load_admin

/bin/systemctl enable tendrl-api
/bin/systemctl start tendrl-api

#/bin/systemctl restart httpd

/bin/systemctl enable tendrl-node-monitoring
/bin/systemctl start tendrl-node-monitoring

/bin/systemctl enable tendrl-performance-monitoring
/bin/systemctl start tendrl-performance-monitoring
EOF

chmod +x /usr/local/setup-script
crontab /etc/cron.d/tendrl
exit 0
%end
