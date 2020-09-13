join_with_comma () {
  ip_array=("$@")
  printf -v joined "%s," "${ip_array[@]}"
  result_string=${joined%,}
}


extract_spotInstance_details() {
  spotinstance_response_file_name=$1
  profile_name=$2
  instance_name_prefix=$2
  
  cnt=$(jq -r ".SpotInstanceRequests | length" "${spotinstance_response_file_name}")
  echo $cnt
  spot_request_ids=($(jq -r '.SpotInstanceRequests[].SpotInstanceRequestId | @sh' "${spotinstance_response_file_name}"))
  spot_response_details_file_name="${instance_name_prefix}-spot-response-details"
  instances_details_file_name="${instance_name_prefix}-instances-details.json"
  
  for ((j=0;j<5;j++))
  do
    
    aws ec2 describe-spot-instance-requests --profile "${profile_name}" --spot-instance-request-ids $(echo "${spot_request_ids[@]}" | sed -e "s/'//g" ) > "${spot_response_details_file_name}"
    success=$(jq -r '[.SpotInstanceRequests[].Status.Code=="fulfilled"]|all' "${spot_response_details_file_name}")
    
    if $success
    then
      instance_ids=($(jq -r '.SpotInstanceRequests[].InstanceId | @sh' "${spot_response_details_file_name}"))    
      break
    fi
    sleep 5
  done
  
  printf -v joined "%s," "${instance_ids[@]}"
  instance_ids_string=$(echo $joined | sed -e "s/'//g")
  instance_ids_string=${instance_ids_string%,}
  
  aws ec2 describe-instances --profile "${profile_name}" --filters=Name=instance-id,Values="${instance_ids_string}" >  "${instances_details_file_name}"
  ec2_public_ips=($( cat "${instances_details_file_name}" | jq -r '.Reservations[0] | .Instances[].PublicIpAddress | @sh')) 
  ec2_private_ips=($( cat "${instances_details_file_name}" | jq -r '.Reservations[0] | .Instances[].PrivateIpAddress | @sh')) 
  echo "ec2 private ips are ${ec2_private_ips[@]}"
}

create_master_node() {
  
  aws ec2 request-spot-instances --spot-price "0.0282" --instance-count 1 --type "persistent" --launch-specification file://master-specification.json --instance-interruption-behavior stop --profile account1> master_spot_response.json
  echo waiting for master node to be created
  extract_spotInstance_details "master_spot_response.json" "account1" "master" 

  if $success
  then
    echo "master instance created"
  else
    echo "creating ec2 failed, please check in console"
  fi

  account1_spot_request_ids=("${spot_request_ids[@]}")
  master_public_ip="${ec2_public_ips[0]}"
  master_private_ip="${ec2_private_ips[0]}"
  echo "master node created, public ip is ${master_public_ip} private ip is ${master_private_ip}"

}

create_account1_worker_nodes() {

  aws ec2 request-spot-instances --spot-price "0.0282" --instance-count 2 --type "persistent" --launch-specification file://account1-worker-specification.json --instance-interruption-behavior stop --profile account1 --profile account1 > account1_workers_spot_response.json
  echo waiting for worker nodes to be created in account1
  extract_spotInstance_details "account1_workers_spot_response.json" "account1" "account1_workers"

  if $success
  then
    echo "account1 worker nodes created"
  else
    echo "creating ec2 failed, please check in console"
  fi
    
  account1_worker_ips=("${ec2_public_ips[@]}")
  account1_spot_request_ids=("${account1_spot_request_ids[@]}" "${spot_request_ids[@]}")
  echo "account1 worker nodes(2) are created, ips are ${account1_worker_ips[@]}" 
  echo "account1 spot instance request ids are ${account1_spot_request_ids[@]}"

}

create_account2_worker_nodes() {

  aws ec2 request-spot-instances --profile account2 --spot-price "0.0282" --instance-count 3 --type "persistent" --launch-specification file://account2-worker-specification.json --instance-interruption-behavior stop > account2_workers_spot_response.json
  echo waiting for worker nodes to be created in account2
  extract_spotInstance_details "account2_workers_spot_response.json" "account2" "account2_workers"

  if $success
  then
    echo "account2 worker nodes created"
  else
    echo "creating ec2 failed, please check in console"
  fi

  account2_spot_request_ids=("${spot_request_ids[@]}")
  account2_worker_ips=("${ec2_public_ips[@]}")
  echo "account2 worker nodes (3) are created, ips are ${account2_worker_ips[@]}" 
  echo "spot instance request ids are ${account2_spot_request_ids[@]}"

}

ec2_params_file_name=$1
ec2_key=$(jq -r '.key_name' "${ec2_params_file_name}")
instance_type=$(jq -r '.instance_type' "${ec2_params_file_name}")
zone=$(jq -r '.zone' "${ec2_params_file_name}")
master_subnet_id=$(jq -r '.account1.master.subnet_id' "${ec2_params_file_name}")
master_sg_id=$(jq -r '.account1.master.sg_id' "${ec2_params_file_name}")
account1_iam_instance_profile=$(jq -r '.account1.iam_instance_profile' "${ec2_params_file_name}")
account2_iam_instance_profile=$(jq -r '.account2.iam_instance_profile' "${ec2_params_file_name}")
account1_worker_subnet_id=$(jq -r '.account1.workers.subnet_id' "${ec2_params_file_name}")
account1_worker_sg_id=$(jq -r '.account1.workers.sg_id' "${ec2_params_file_name}")
account2_worker_subnet_id=$(jq -r '.account2.workers.subnet_id' "${ec2_params_file_name}")
account2_worker_sg_id=$(jq -r '.account2.workers.sg_id' "${ec2_params_file_name}")


cat ec2-instance-specification.json | sed -e "s/key_name/${ec2_key}/" \
                                          -e "s/subnet_id/${master_subnet_id}/" \
                                          -e "s/sg_id/${master_sg_id}/" \
                                          -e "s/instance_type/${instance_type}/" \
                                          -e "s/zone/${zone}/" \
                                          -e "s/iam_instance_profile/${account1_iam_instance_profile}/"  > master-specification.json


cat ec2-instance-specification.json | sed -e "s/key_name/${ec2_key}/" \
                                          -e "s/subnet_id/${account1_worker_subnet_id}/" \
                                          -e "s/sg_id/${account1_worker_sg_id}/" \
                                          -e "s/instance_type/${instance_type}/" \
                                          -e "s/zone/${zone}/" \
                                          -e "s/iam_instance_profile/${account1_iam_instance_profile}/"  > account1-worker-specification.json


cat ec2-instance-specification.json | sed -e "s/key_name/${ec2_key}/" \
                                          -e "s/subnet_id/${account2_worker_subnet_id}/" \
                                          -e "s/sg_id/${account2_worker_sg_id}/" \
                                          -e "s/instance_type/${instance_type}/" \
                                          -e "s/zone/${zone}/" \
                                          -e "s/iam_instance_profile/${account2_iam_instance_profile}/"  > account2-worker-specification.json

ssh-keygen -t rsa -b 4096 -f ec2-key << EOF


EOF

aws ec2 delete-key-pair --key-name "${ec2_key}" --profile account1
aws ec2 import-key-pair --key-name "${ec2_key}" --public-key-material "fileb://${ec2_key}.pub" --profile account1
aws ec2 delete-key-pair --key-name "${ec2_key}" --profile account2
aws ec2 import-key-pair --key-name "${ec2_key}" --public-key-material "fileb://${ec2_key}.pub" --profile account2

create_master_node
create_account1_worker_nodes
create_account2_worker_nodes


worker_ips=("${account1_worker_ips[@]}" "${account2_worker_ips[@]}")
join_with_comma "${worker_ips[@]}"
worker_ips_string=$(echo $result_string | sed "s@[']@\"@g")

join_with_comma "${account1_spot_request_ids[@]}"
account1_spot_request_ids_string=$(echo $result_string | sed "s@[']@\"@g")

join_with_comma "${account2_spot_request_ids[@]}"
account2_spot_request_ids_string=$(echo $result_string | sed "s@[']@\"@g")

master_private_ip=$(echo $master_private_ip | sed -e "s/'//g")
master_public_ip=$(echo $master_public_ip | sed -e "s/'//g")

cat "ec2-details-template.json" | sed -e "s/master_public_ip/${master_public_ip}/" \
                             -e "s/master_private_ip/${master_private_ip}/" \
                             -e "s@[\"]worker_ips_string[\"]@${worker_ips_string}@" \
                             -e "s@[\"]account1_spot_request_ids_string[\"]@${account1_spot_request_ids_string}@" \
                             -e "s@[\"]account2_spot_request_ids_string[\"]@${account2_spot_request_ids_string}@" > ec2-details.json
