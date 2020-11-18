#!/bin/bash
apiserver_ip=10.0.0.203
apiserver_token=abcdef.0123456789abcdef
apiserver_cert_hash=31d4e7c97c29b35c275a72403f8f2e1e17ffc72f3fd610db2afaf5653e0ed9db
interface_name=$(ifconfig | awk '/ens/ {print $1}' | sed 's/.$//')
node_name=$(ifconfig "${interface_name}"| awk '/inet /{print $0}' | awk '$4!="255.0.0.0" {print $2}')
sudo kubeadm join "${apiserver_ip}":443 --token="${apiserver_token}" --discovery-token-ca-cert-hash sha256:"${apiserver_cert_hash}" --node-name="${node_name}"
