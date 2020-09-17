#!/bin/bash
master_private_ip=$1
domain_name=$2
ec2_key=${3:-"ec2-key"}
ec2_key="$(pwd)/${ec2_key}"

ssh-keygen -f "/home/gajanan/.ssh/known_hosts" -R "${domain_name}"

ssh -i "${ec2_key}" -o StrictHostKeyChecking=no "ubuntu@${domain_name}" "bash -s" -- << EOF
sudo cp /etc/kubernetes/pki/ca.crt /home/ubuntu/ca.crt
EOF

scp -i "${ec2_key}" -o StrictHostKeyChecking=no  "ubuntu@${domain_name}:/home/ubuntu/ca.crt" ~/ca.crt
if [ -d ~/.kube ]
then 
  rm -rd ~/.kube
fi
mkdir ~/.kube
scp -i "${ec2_key}" -o StrictHostKeyChecking=no "ubuntu@${domain_name}:/home/ubuntu/.kube/config" ~/.kube/config

if [ -f /usr/local/share/ca-certificates/ca.crt ]
then
  sudo rm /usr/local/share/ca-certificates/ca.crt
  sudo update-ca-certificates -f
fi

sudo cp ~/ca.crt /usr/local/share/ca-certificates/ca.crt
sudo update-ca-certificates

sed -e "s/${master_private_ip}/${domain_name}/g" ~/.kube/config > temp_config
cat temp_config > ~/.kube/config
rm temp_config

current_dir=$(pwd)
cd ~/go/src/github.com/kubernetes-sigs/aws-ebs-csi-driver
#scp -i "${ec2_key}" -o StrictHostKeyChecking=no deploy/kubernetes/secrets/aws_accounts.yaml  "ubuntu@${domain_name}:/home/ubuntu/aws_accounts.yaml"
#scp -i "${ec2_key}" -o StrictHostKeyChecking=no deploy/kubernetes/secrets/credentials "ubuntu@${domain_name}:/home/ubuntu/credentials"

while kubectl get node | grep "NotReady" ;
do
  echo "k8s worker nodes are not yet ready, sleeping for 10s"
  sleep 10s
done

kubectl apply -k deploy/kubernetes/secrets/
kubectl apply -f deploy/kubernetes/cluster/crd_snapshotter.yaml
kubectl apply -k deploy/kubernetes/overlays/alpha/

cd "${current_dir}"
while kubectl get pod -n kube-system | grep csi | grep -v Running || \
      kubectl get statefulset ebs-snapshot-controller -n kube-system  | grep -v READY | awk '$2!="1/1"' | grep ebs ;
do
  echo "waiting for csi driver to come online, sleeping for 10s"
  sleep 10s
done
echo "Aws ebs csi driver installed" 
