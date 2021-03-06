interface_name=$(ifconfig | awk '/ens/ {print $1}' | sed 's/.$//')
node_name=$(ifconfig "${interface_name}"| awk '/inet /{print $0}' | awk '$4!="255.0.0.0" {print $2}')
sudo kubeadm join "${apiserver_ip}":443 --token="${apiserver_token}" --discovery-token-ca-cert-hash sha256:"${apiserver_cert_hash}" --node-name="${node_name}"
