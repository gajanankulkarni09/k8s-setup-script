#!/bin/bash
apiserver_ip=10.2.0.223
apiserver_token=abcdef.0123456789abcdef
apiserver_cert_hash=580a0ad0952d3ad69f8bf496a060412581da1e4ea5ff4098cbad8e2ba2d66b9b
interface_name=$(ifconfig | awk '/ens/ {print $1}' | sed 's/.$//')
node_name=$(ifconfig "${interface_name}"| awk '/inet /{print $0}' | awk '$4!="255.0.0.0" {print $2}')
sudo kubeadm join "${apiserver_ip}":443 --token="${apiserver_token}" --discovery-token-ca-cert-hash sha256:"${apiserver_cert_hash}" --node-name="${node_name}"
