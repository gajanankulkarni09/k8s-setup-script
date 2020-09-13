#!/bin/bash
sudo apt install jq -y
ec2_key="ec2-key"
cat ec2-parameters-template.json | sed -e "s/key_name/${ec2_key}/g2" \
                                          -e "s/instance_type/m5.large/g2" \
                                          -e "s/zone/ap-south-1b/g2" \
                                          -e "s/account1_iam_instance_profile/k8s-ec2-ebs-provisioner-role/" \
                                          -e "s/master_subnet_id/subnet-0f47ec4d89b9d85cb/" \
                                          -e "s/master_sg_id/sg-014c603a13a037b55/"  \
                                          -e "s/account1_workers_subnet_id/subnet-0cb52da0c85a58f96/" \
                                          -e "s/account1_workers_sg_id/sg-09b9f2a43f3e22c79/" \
                                          -e "s/account2_iam_instance_profile/k8s-ec2-ebs-provisioner-policy/" \
                                          -e "s/account2_workers_subnet_id/subnet-0738d1b5476344058/" \
                                          -e "s/account2_workers_sg_id/sg-021a58d09979ee197/"  > ec2-parameters.json

ec2_details_file_name="ec2-details.json"
/bin/bash ./create-ec2.sh "ec2-parameters.json"

# "first.pem" "account2-ec2-key.pem" "account2-ec2-key.pem" "account2-ec2-key.pem")
worker_ips=($(jq -r '.worker_ips | @sh' "${ec2_details_file_name}"))

master_private_ip=$(jq -r ".master_ips.private_ip" "${ec2_details_file_name}")
master_private_ip=$(echo $master_private_ip | sed -e "s/'//g")
master_public_ip=$(jq -r ".master_ips.public_ip" "${ec2_details_file_name}")
master_public_ip=$(echo $master_public_ip | sed -e "s/'//g")

bootstrap_token_value="abcdef.0123456789abcdef"

sed -e "s/master_private_ip/${master_private_ip}/" \
    -e "s/bootstrap_token_value/${bootstrap_token_value}/" "kubeadm-config.yaml" > temp
mv temp kubeadm-config.yaml

sleep 3m

printf "ubuntu@%s\n" "${worker_ips[@]}" |  sed -e "s/'//g" > ec2-host
#export PDSH_SSH_ARGS_APPEND=" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${ec2_key}"

scp -i "${ec2_key}" -o StrictHostKeyChecking=no kubeadm-config.yaml "ubuntu@${master_public_ip}":config.yaml
echo "installing prerequisites on master"
ssh -i "${ec2_key}" -o StrictHostKeyChecking=no "ubuntu@${master_public_ip}" "bash -s" -- < install-prerequisites.sh
echo "installing k8s on master"
ssh -i "${ec2_key}" -o StrictHostKeyChecking=no "ubuntu@${master_public_ip}" "bash -s" -- < install-master.sh
echo "generating worker node script"
{ cat install-prerequisites.sh ;\
  ssh -i "${ec2_key}" -o StrictHostKeyChecking=no "ubuntu@${master_public_ip}" "bash -s" -- < generate-workernode-script.sh "${bootstrap_token_value}"; } > install-workernode.sh

echo "installions on worker nodes"
#pdsh -w ^ec2-host -x "${master_public_ip}" -R ssh -l ubuntu < install-workernode.sh

 parallel-ssh -h ec2-host -x " -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${ec2_key}" -t 0 -I <install-workernode.sh
# for ((i=0;i<"${#worker_ips[@]}";i++))
# do
#     echo "worker node ${i}"
#     temp_ip=$(echo "${worker_ips[i]}" | sed -e "s/'//g" )
#     echo "installing prerequisites on worker node ${i}"
#     ssh -i  "${ec2_key}" -o StrictHostKeyChecking=no "ubuntu@${temp_ip}" "bash -s" -- < install-prerequisites.sh
#     echo "installing k8s on worker node ${i}"
#     ssh -i "${ec2_key}" -o StrictHostKeyChecking=no "ubuntu@${temp_ip}" "bash -s" -- < install-workernode.sh
# done

