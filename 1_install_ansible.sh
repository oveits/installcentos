#!/bin/bash

# Installs ansible on a CentOS system
#
# Variables:
# - REMOTE optional
# - IP     required in case REMOTE != "true"

# install updates
yum update -y

# install the following base packages
yum install -y  wget git zile nano net-tools docker-1.13.1\
				bind-utils iptables-services \
				bridge-utils bash-completion \
				kexec-tools sos psacct openssl-devel \
				httpd-tools NetworkManager \
				python-cryptography python2-pip python-devel  python-passlib \
				java-1.8.0-openjdk-headless "@Development Tools"

#install epel
yum -y install epel-release

# Disable the EPEL repository globally so that is not accidentally used during later steps of the installation
sed -i -e "s/^enabled=1/enabled=0/" /etc/yum.repos.d/epel.repo

# remove existing Ansible versions:#
yum remove -y ansible

# install the packages for Ansible
curl -O http://cbs.centos.org/kojifiles/packages/ansible/2.6.5/1.el7/noarch/ansible-2.6.5-1.el7.noarch.rpm
# note: epel is needed to install dependencies like python-keyczar
yum -y --enablerepo=epel install ansible-2.6.5-1.el7.noarch.rpm
# exclude ansible from automatic updates:
cat /etc/yum.conf | grep -v -q 'exclude=ansible' && echo "exclude=ansible" >> /etc/yum.conf
yum -y --enablerepo=epel install pyOpenSSL

# prepare ansible target in case of local install:
if [ "$REMOTE" != "true" ] && [ ! -f ~/.ssh/id_rsa ]; then
	ssh-keygen -q -f ~/.ssh/id_rsa -N ""
	cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
	ssh -o StrictHostKeyChecking=no root@$IP "pwd" < /dev/null
fi
