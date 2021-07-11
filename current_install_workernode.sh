#!/bin/bash
apiserver_ip=10.2.0.76
apiserver_token=abcdef.0123456789abcdef
apiserver_cert_hash=9a6c86fb8e4eb25b82040867efd5abe2daa46cea44bfaa80a4835786f855e34e
interface_name=$(ifconfig | awk '/ens/ {print $1}' | sed 's/.$//')
node_name=$(ifconfig "${interface_name}"| awk '/inet /{print $0}' | awk '$4!="255.0.0.0" {print $2}')
sudo kubeadm join "${apiserver_ip}":443 --token="${apiserver_token}" --discovery-token-ca-cert-hash sha256:"${apiserver_cert_hash}" --node-name="${node_name}"
