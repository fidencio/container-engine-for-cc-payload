#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

die() {
	msg="$*"
	echo "ERROR: $msg" >&2
	exit 1
}

function get_container_engine() {
	local container_engine=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.nodeInfo.containerRuntimeVersion}' | awk -F '[:]' '{print $1}')
	if [ "${container_engine}" != "containerd" ]; then
		die "${container_engine} is not yet supported"
	fi

	echo "$container_engine"	
}

function set_container_engine() {
	# Those are intentionally not set as local

	container_engine=$(get_container_engine)
}

function install_artifacts() {
	echo "Copying containerd-for-cc artifacts onto host"

	local artifacts_dir="/opt/confidential-containers-pre-install-artifacts"

	cp -a ${artifacts_dir}/opt/confidential-containers/* /opt/confidential-containers/
	chmod +x /opt/confidential-containers/bin/containerd

	cp -a ${artifacts_dir}/etc/systemd/system/* /etc/systemd/system/
}

function uninstall_artifacts() {
	echo "Removing containerd-for-cc artifacts from host"

	rm -f /opt/confidential-containers/bin/containerd
	rm -f /etc/systemd/system/${container_engine}.service.d/${container_engine}-for-cc-override.conf
}

function restart_systemd_service() {
	systemctl daemon-reload
	systemctl restart "${container_engine}"
}

label_node() {
	case "${1}" in
	install)
		kubectl label node "${NODE_NAME}" cc-preinstall/done=true
		;;
	uninstall)
		kubectl label node "${NODE_NAME}" cc-postuninstall/done=true
		;;
	*)
		;;
	esac
}

function print_help() {
	echo "Help: ${0} [install/uninstall]"
}

function main() {
	# script requires that user is root
	local euid=$(id -u)
	if [ ${euid} -ne 0 ]; then
		die "This script must be run as root"
	fi

	local action=${1:-}
	if [ -z "${action}" ]; then
		print_help && die ""
	fi

	set_container_engine

	case "${action}" in
	install)
		install_artifacts
		;;
	uninstall)
		uninstall_artifacts
		;;
	*)
		print_help
		;;
	esac

	restart_systemd_service
	label_node "${action}"


	# It is assumed this script will be called as a daemonset. As a result, do
	# not return, otherwise the daemon will restart and reexecute the script.
	sleep infinity
}

main "$@"
