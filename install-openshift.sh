#!/bin/bash

## see: https://youtu.be/aqXSbDZggK4

## Compute default SCRIPT_REPO:
REPO="$(git remote -v | grep fetch | awk '{print $2}' | awk -F 'https://github.com/' '{print $2}')"
BRANCH="$(git status | grep 'On branch' | awk '{print $3}')"
SCRIPT_REPO_DEFAULT="https://raw.githubusercontent.com/$REPO/$BRANCH"

## Default variables to use
export INTERACTIVE=${INTERACTIVE:="true"}
export PVS=${INTERACTIVE:="true"}
export PASSWORD=${PASSWORD:=aqXSbDZggK4}
export VERSION=${VERSION:="3.10"}
export SCRIPT_REPO=${SCRIPT_REPO:="$SCRIPT_REPO_DEFAULT"}
export API_PORT=${API_PORT:="8443"}
export METRICS="True"
export LOGGING="True"

# TODO: run the following block on the master for setting the variables locally:
export DOMAIN=${DOMAIN:="$(curl -s ipinfo.io/ip).nip.io"}
export USERNAME=${USERNAME:="$(whoami)"}
# TODO: need to make a difference between the IP reachable from the Ansible installer and the local IP of the master
# TODO: moreover, need to make a difference between master and nodes
export IP=${IP:="$(ip route get 8.8.8.8 | awk '{print $NF; exit}')"}
# TODO: needs to be performed on the master to set METRICS and LOGGING locally
memory=$(cat /proc/meminfo | grep MemTotal | sed "s/MemTotal:[ ]*\([0-9]*\) kB/\1/")
#
if [ "$memory" -lt "4194304" ]; then
	export METRICS="False"
fi
#
if [ "$memory" -lt "8388608" ]; then
	export LOGGING="False"
fi

## Make the script interactive to set the variables
if [ "$INTERACTIVE" = "true" ]; then
	read -rp "Domain to use: ($DOMAIN): " choice;
	if [ "$choice" != "" ] ; then
		export DOMAIN="$choice";
	fi

	read -rp "Username: ($USERNAME): " choice;
	if [ "$choice" != "" ] ; then
		export USERNAME="$choice";
	fi

	read -rp "Password: ($PASSWORD): " choice;
	if [ "$choice" != "" ] ; then
		export PASSWORD="$choice";
	fi

	read -rp "OpenShift Version: ($VERSION): " choice;
	if [ "$choice" != "" ] ; then
		export VERSION="$choice";
	fi
	read -rp "IP: ($IP): " choice;
	if [ "$choice" != "" ] ; then
		export IP="$choice";
	fi

	read -rp "API Port: ($API_PORT): " choice;
	if [ "$choice" != "" ] ; then
		export API_PORT="$choice";
	fi 

	echo

fi

echo "******"
echo "* Your domain is $DOMAIN "
echo "* Your IP is $IP "
echo "* Your username is $USERNAME "
echo "* Your password is $PASSWORD "
echo "* OpenShift version: $VERSION "
echo "******"

# install ansible
bash 1_install_ansible.sh

# install prerequisites
bash 2_install-openshift-prerequisites.sh

[ ! -d openshift-ansible ] && git clone https://github.com/openshift/openshift-ansible.git

cd openshift-ansible && git fetch && git checkout release-3.10 && cd ..

curl -o inventory.download $SCRIPT_REPO/inventory.ini
envsubst < inventory.download > inventory

# add proxy in inventory if proxy variables are set
if [ ! -z "${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy}}}}" ]; then
	echo >> inventory
	echo "openshift_http_proxy=\"${HTTP_PROXY:-${http_proxy:-${HTTPS_PROXY:-${https_proxy}}}}\"" >> inventory
	echo "openshift_https_proxy=\"${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy}}}}\"" >> inventory
	if [ ! -z "${NO_PROXY:-${no_proxy}}" ]; then
		__no_proxy="${NO_PROXY:-${no_proxy}},${IP},.${DOMAIN}"
	else
		__no_proxy="${IP},.${DOMAIN}"
	fi
	echo "openshift_no_proxy=\"${__no_proxy}\"" >> inventory
fi

# DONE: read path from inventory, and handle, if not found
HTPASSWD_PATH=$(grep openshift_master_htpasswd_file inventory | awk -F '=' '{print $2}' | sed "s/^'\([^']*\)'.*$/\1/g")

if [ "$HTPASSWD_PATH" != "" ]; then
       # TODO: perform the next two commands on the master
       mkdir -p $(dirname $HTPASSWD_PATH)
       touch $HTPASSWD_PATH
else
       echo "WARNING: openshift_master_htpasswd_file not found in inventory"
       echo "Are you using another method for authentication?"
fi

ansible-playbook -i inventory openshift-ansible/playbooks/prerequisites.yml
ansible-playbook -i inventory openshift-ansible/playbooks/deploy_cluster.yml

if [ "$HTPASSWD_PATH" != "" ]; then
       # TODO: perform on the master:
       htpasswd -b /etc/origin/master/htpasswd ${USERNAME} ${PASSWORD}
fi

# TODO: perform on the master or make sure oc is running on the Ansible machine and is connected to the master
oc adm policy add-cluster-role-to-user cluster-admin ${USERNAME}

# TODO: perform on the master:
if [ "$PVS" = "true" ]; then
	for i in `seq 1 200`;
	do
		DIRNAME="vol$i"
		mkdir -p /mnt/data/$DIRNAME 
		chcon -Rt svirt_sandbox_file_t /mnt/data/$DIRNAME
		chmod 777 /mnt/data/$DIRNAME
		
		sed "s/name: vol/name: vol$i/g" vol.yaml > oc_vol.yaml
		sed -i "s/path: \/mnt\/data\/vol/path: \/mnt\/data\/vol$i/g" oc_vol.yaml
		oc create -f oc_vol.yaml
		echo "created volume $i"
	done
	rm oc_vol.yaml
fi

echo "******"
echo "* Your console is https://console.$DOMAIN:$API_PORT"
echo "* Your username is $USERNAME "
echo "* Your password is $PASSWORD "
echo "*"
echo "* Login using:"
echo "*"
echo "$ oc login -u ${USERNAME} -p ${PASSWORD} https://console.$DOMAIN:$API_PORT/"
echo "******"

# TODO: run on the master? Or in the Ansible machine?
oc login -u ${USERNAME} -p ${PASSWORD} https://console.$DOMAIN:$API_PORT/
