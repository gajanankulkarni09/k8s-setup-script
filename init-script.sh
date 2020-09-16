#!/bin/bash
cd /home/gajanan/go/src/github.com/kubernetes-sigs/aws-ebs-csi-driver
scp -i /home/gajanan/k8s-setup-script/ec2-key deploy/kubernetes/secrets/aws_accounts.yaml  ubuntu@gkawslearning.life:/home/ubuntu/aws_accounts.yaml
scp -i /home/gajanan/k8s-setup-script/ec2-key deploy/kubernetes/secrets/credentials ubuntu@gkawslearning.life:/home/ubuntu/credentials
ssh -i /home/gajanan/k8s-setup-script/ec2-key ubuntu@gkawslearning.life "bash -s" -- << EOF
sudo cp /etc/kubernetes/pki/ca.crt /home/ubuntu/ca.crt
git clone "https://github.com/gajanankulkarni09/aws-ebs-csi-driver"
cd aws-ebs-csi-driver
git checkout cross-accounts-support
cat /home/ubuntu/aws_accounts.yaml > deploy/kubernetes/secrets/aws_accounts.yaml
cat /home/ubuntu/credentials > deploy/kubernetes/secrets/credentials
kubectl apply -k deploy/kubernetes/secrets/
kubectl apply -f deploy/kubernetes/cluster/crd_snapshotter.yaml
kubectl apply -k deploy/kubernetes/overlays/alpha/
EOF
scp -i /home/gajanan/k8s-setup-script/ec2-key ubuntu@gkawslearning.life:/home/ubuntu/ca.crt /home/gajanan/ca.crt
if [ -d ~/.kube ]
then 
  rm -rd ~/.kube
fi
mkdir ~/.kube
scp -i /home/gajanan/k8s-setup-script/ec2-key ubuntu@gkawslearning.life:/home/ubuntu/.kube/config /home/gajanan/.kube/config

if [ -f /usr/local/share/ca-certificates/ca.crt ]
then
  sudo rm /usr/local/share/ca-certificates/ca.crt
  sudo update-ca-certificates -f
fi

sudo cp ~/ca.crt /usr/local/share/ca-certificates/ca.crt
sudo update-ca-certificates

master_private_ip=$1
domain_name=$2
sed -e "s/${master_private_ip}/${domain_name}/g" ~/.kube/config > temp_config
cat temp_config > ~/.kube/config
rm temp_config
