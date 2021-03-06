#!/bin/bash

CERT_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt \
| openssl rsa -pubin -outform der 2>/dev/null \
| openssl dgst -sha256 -hex \
| sed 's/^.* //')

TOKEN=$1

IP=$(kubectl get nodes -lnode-role.kubernetes.io/master -o json \
| jq -r '.items[0].status.addresses[] | select(.type=="InternalIP") | .address')
PORT=443

# echo "#!/bin/bash" > temp.sh
# echo "sudo kubeadm join $IP:$PORT \
# --token=$TOKEN --discovery-token-ca-cert-hash sha256:$CERT_HASH" >> temp.sh

echo "${IP} ${TOKEN} ${CERT_HASH}" > temp
cat temp
