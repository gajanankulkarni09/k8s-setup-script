join_with_comma () {
  ip_array=("$@")
  printf -v joined "%s," "${ip_array[@]}"
  result_string=${joined%,}
}


extract_spotInstance_details() {
  spotinstance_response_file_name=$1
  instance_name_prefix=$2
  
  cnt=$(jq -r ".SpotInstanceRequests | length" "${spotinstance_response_file_name}")
  echo $cnt
  spot_request_ids=($(jq -r '.SpotInstanceRequests[].SpotInstanceRequestId | @sh' "${spotinstance_response_file_name}"))
  spot_response_details_file_name="${instance_name_prefix}-spot-response-details"
  instances_details_file_name="${instance_name_prefix}-instances-details.json"
  
  for ((j=0;j<5;j++))
  do
    
    aws ec2 describe-spot-instance-requests --spot-instance-request-ids $(echo "${spot_request_ids[@]}" | sed -e "s/'//g" ) > "${spot_response_details_file_name}"
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
  
  aws ec2 describe-instances  --filters=Name=instance-id,Values="${instance_ids_string}" >  "${instances_details_file_name}"
  ec2_public_ips=($( cat "${instances_details_file_name}" | jq -r '.Reservations[0] | .Instances[].PublicIpAddress | @sh')) 
  ec2_private_ips=($( cat "${instances_details_file_name}" | jq -r '.Reservations[0] | .Instances[].PrivateIpAddress | @sh')) 
  echo "ec2 private ips are ${ec2_private_ips[@]}"
}

create_master_node() {
  
  export AWS_PROFILE=account1
  aws ec2 request-spot-instances --spot-price "0.0299" --instance-count 1 --type "persistent" --launch-specification file://master-specification.json --instance-interruption-behavior stop > master_spot_response.json
  echo waiting for master node to be created
  extract_spotInstance_details "master_spot_response.json"  "master" 

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

  export AWS_PROFILE=account1
  aws ec2 request-spot-instances --spot-price "0.0299" --instance-count 2 --type "persistent" --launch-specification file://account1-worker-specification.json --instance-interruption-behavior stop > account1_workers_spot_response.json
  echo waiting for worker nodes to be created in account1
  extract_spotInstance_details "account1_workers_spot_response.json" "account1_workers"

  if $success
  then
    echo "account1 worker nodes created"
  else
    echo "creating ec2 failed, please check in console"
  fi
    
  account1_worker_ips=("${ec2_public_ips[@]}")
  account1_worker_private_ips=("${ec2_private_ips[@]}")
  account1_spot_request_ids=("${account1_spot_request_ids[@]}" "${spot_request_ids[@]}")
  echo "account1 worker nodes(2) are created, ips are ${account1_worker_ips[@]}" 
  echo "account1 spot instance request ids are ${account1_spot_request_ids[@]}"

}

create_account2_worker_nodes() {
  export AWS_PROFILE=account2
  aws ec2 request-spot-instances  --spot-price "0.0299" --instance-count 3 --type "persistent" --launch-specification file://account2-worker-specification.json --instance-interruption-behavior stop > account2_workers_spot_response.json
  echo waiting for worker nodes to be created in account2
  extract_spotInstance_details "account2_workers_spot_response.json"  "account2_workers"

  if $success
  then
    echo "account2 worker nodes created"
  else
    echo "creating ec2 failed, please check in console"
  fi

  account2_spot_request_ids=("${spot_request_ids[@]}")
  account2_worker_ips=("${ec2_public_ips[@]}")
  account2_worker_private_ips=("${ec2_private_ips[@]}")
  echo "account2 worker nodes (3) are created, ips are ${account2_worker_ips[@]}" 
  echo "spot instance request ids are ${account2_spot_request_ids[@]}"

}

ec2_params_file_name=$1
ec2_key=$(jq -r '.key_name' "${ec2_params_file_name}")
instance_type=$(jq -r '.instance_type' "${ec2_params_file_name}")
zone=$(jq -r '.zone' "${ec2_params_file_name}")
#master_subnet_id=$(jq -r '.account1.master.subnet_id' "${ec2_params_file_name}")
#master_sg_id=$(jq -r '.account1.master.sg_id' "${ec2_params_file_name}")
account1_iam_instance_profile=$(jq -r '.account1.iam_instance_profile' "${ec2_params_file_name}")
account2_iam_instance_profile=$(jq -r '.account2.iam_instance_profile' "${ec2_params_file_name}")
#account1_worker_subnet_id=$(jq -r '.account1.workers.subnet_id' "${ec2_params_file_name}")
#account1_worker_sg_id=$(jq -r '.account1.workers.sg_id' "${ec2_params_file_name}")
#account2_worker_subnet_id=$(jq -r '.account2.workers.subnet_id' "${ec2_params_file_name}")
#account2_worker_sg_id=$(jq -r '.account2.workers.sg_id' "${ec2_params_file_name}")



ssh-keygen -t rsa -b 4096 -f ec2-key << EOF


EOF
chmod 400 ec2-key


host_public_ip=$(lwp-request -o text checkip.dyndns.org | awk '{ print $NF }')
export AWS_PROFILE=account1

# create vpc for account1
aws ec2 create-vpc --cidr-block 10.2.0.0/16  >account1-vpc
account1_vpc_id=$(jq -r '.Vpc.VpcId' account1-vpc)
aws ec2 create-tags --resources "${account1_vpc_id}" --tags Key=Name,Value=k8s-cluster 

# create igw for account1
aws ec2 create-internet-gateway  > account1_vpc_ig 
account1_vpc_ig=$(jq -r '.InternetGateway.InternetGatewayId' account1_vpc_ig)
aws ec2 attach-internet-gateway --internet-gateway-id "${account1_vpc_ig}" --vpc-id "${account1_vpc_id}" 
aws ec2 create-tags --resources "${account1_vpc_ig}" --tags Key=Name,Value=k8s-vpc-ig 

# create  route table for master subnet account1
aws ec2 create-route-table --vpc-id "${account1_vpc_id}"  >account1-master-rtb
account1_master_rtb_id=$(jq -r '.RouteTable.RouteTableId' account1-master-rtb)
aws ec2 create-tags --resources "${account1_master_rtb_id}" --tags Key=Name,Value=k8s-master-rtb 
aws ec2 create-route --route-table-id "${account1_master_rtb_id}" --destination-cidr-block 0.0.0.0/0 --gateway-id "${account1_vpc_ig}" 

# create master subnet in account1
aws ec2 create-subnet --cidr-block 10.2.0.0/24 --vpc-id "${account1_vpc_id}" --availability-zone "ap-south-1b" >account1-master-subnet
master_subnet_id=$(jq -r '.Subnet.SubnetId' account1-master-subnet)
aws ec2 create-tags --resources "${master_subnet_id}" --tags Key=Name,Value=k8s-master-subnet 
aws ec2 modify-subnet-attribute --subnet-id "${master_subnet_id}" --map-public-ip-on-launch 
aws ec2 associate-route-table --route-table-id "${account1_master_rtb_id}" --subnet-id "${master_subnet_id}" 

# create  route table for worker subnet account1
aws ec2 create-route-table --vpc-id "${account1_vpc_id}"  >account1-worker-rtb
account1_worker_rtb_id=$(jq -r '.RouteTable.RouteTableId' account1-worker-rtb)
aws ec2 create-tags --resources "${account1_worker_rtb_id}" --tags Key=Name,Value=k8s-worker-rtb 
aws ec2 create-route --route-table-id "${account1_worker_rtb_id}" --destination-cidr-block 0.0.0.0/0 --gateway-id "${account1_vpc_ig}" 

#create worker subnet in account1
aws ec2 create-subnet --cidr-block 10.2.1.0/24 --vpc-id "${account1_vpc_id}" --availability-zone "ap-south-1b" >account1-worker-subnet
account1_worker_subnet_id=$(jq -r '.Subnet.SubnetId' account1-worker-subnet)
aws ec2 create-tags --resources "${account1_worker_subnet_id}" --tags Key=Name,Value=k8s-worker-subnet 
aws ec2 modify-subnet-attribute --subnet-id "${account1_worker_subnet_id}" --map-public-ip-on-launch 
aws ec2 associate-route-table --route-table-id "${account1_worker_rtb_id}" --subnet-id "${account1_worker_subnet_id}" 

export AWS_PROFILE=account2

# create vpc for account2
aws ec2 create-vpc --cidr-block 10.3.0.0/16  >account2-vpc
account2_vpc_id=$(jq -r '.Vpc.VpcId' account2-vpc)
aws ec2 create-tags --resources "${account2_vpc_id}" --tags Key=Name,Value=k8s-vpc 

# create internet gateway in account2
aws ec2 create-internet-gateway  > account2_vpc_ig 
account2_vpc_ig=$(jq -r '.InternetGateway.InternetGatewayId' account2_vpc_ig)
aws ec2 attach-internet-gateway --internet-gateway-id "${account2_vpc_ig}" --vpc-id "${account2_vpc_id}" 
aws ec2 create-tags --resources "${account2_vpc_ig}" --tags Key=Name,Value=k8s-vpc-ig 

# create  route table for worker subnet in account2
aws ec2 create-route-table --vpc-id "${account2_vpc_id}"  >account2-worker-rtb
account2_worker_rtb_id=$(jq -r '.RouteTable.RouteTableId' account2-worker-rtb)
aws ec2 create-tags --resources "${account2_worker_rtb_id}" --tags Key=Name,Value=k8s-worker-rtb 
aws ec2 create-route --route-table-id "${account2_worker_rtb_id}" --destination-cidr-block 0.0.0.0/0 --gateway-id "${account2_vpc_ig}" 

#create worker subnet in account2
aws ec2 create-subnet --cidr-block 10.3.0.0/24 --vpc-id "${account2_vpc_id}" --availability-zone "ap-south-1b" >account2-worker-subnet
account2_worker_subnet_id=$(jq -r '.Subnet.SubnetId' account2-worker-subnet)
aws ec2 create-tags --resources "${account2_worker_subnet_id}" --tags Key=Name,Value=k8s-worker-subnet 
aws ec2 modify-subnet-attribute --subnet-id "${account2_worker_subnet_id}" --map-public-ip-on-launch 
aws ec2 associate-route-table --route-table-id "${account2_worker_rtb_id}" --subnet-id "${account2_worker_subnet_id}" 

# create VPC peering between vpc of 2 accounts
aws ec2 create-vpc-peering-connection --vpc-id "${account1_vpc_id}" --peer-vpc-id "${account2_vpc_id}" --peer-owner-id "${account2_id}" --profile account1 > vpc-peering-request
vpc_peering_connection_id=$(jq -r '.VpcPeeringConnection.VpcPeeringConnectionId' vpc-peering-request)
aws ec2 create-tags --resources "${vpc_peering_connection_id}" --tags Key=Name,Value=k8s-vpc-peering --profile account1
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id  "${vpc_peering_connection_id}" 

aws ec2 create-route --route-table-id "${account1_master_rtb_id}" --destination-cidr-block 10.3.0.0/16 --vpc-peering-connection-id "${vpc_peering_connection_id}" --profile account1
aws ec2 create-route --route-table-id "${account1_worker_rtb_id}" --destination-cidr-block 10.3.0.0/16 --vpc-peering-connection-id "${vpc_peering_connection_id}" --profile account1
aws ec2 create-route --route-table-id "${account2_worker_rtb_id}" --destination-cidr-block 10.2.0.0/16 --vpc-peering-connection-id "${vpc_peering_connection_id}" 

export AWS_PROFILE=account1

aws ec2 delete-key-pair --key-name "${ec2_key}" 
aws ec2 import-key-pair --key-name "${ec2_key}" --public-key-material "fileb://${ec2_key}.pub" 

aws ec2 create-security-group --group-name aws-k8s-master-sg  --vpc-id "${account1_vpc_id}" --description "k8s master security group" > master-security-group
master_sg_id=$(jq -r '.GroupId' master-security-group)
aws ec2 create-security-group --group-name aws-k8s-worker-sg --description "k8s worker security group" --vpc-id  "${account1_vpc_id}" > account1-worker-security-group
account1_worker_sg_id=$(jq -r '.GroupId' account1-worker-security-group)
aws ec2 create-security-group --group-name aws-k8s-worker-sg --description "k8s worker security group" --vpc-id  "${account2_vpc_id}" --profile account2 > account2-worker-security-group
account2_worker_sg_id=$(jq -r '.GroupId' account2-worker-security-group)

#master security group settings below
#API server port
aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol tcp --port 443 --source-group "${master_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol tcp --port 443 --source-group "${account1_worker_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol tcp --port 443  --group-owner "${account2_id}" --source-group "${account2_worker_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol tcp --port 443 --cidr "${host_public_ip}/32"

#ssh port
aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol tcp --port 22 --cidr "${host_public_ip}/32"

#etcd port
aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol tcp --port 2379-2380 --source-group "${master_sg_id}"

#kubelet port 
aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol tcp --port 10250-10252 --source-group "${master_sg_id}"

#dns ports
aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol tcp --port 53 --source-group "${master_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol tcp --port 53 --source-group "${account1_worker_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol tcp --port 53 --group-owner "${account2_id}" --source-group "${account2_worker_sg_id}"

aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol udp --port 53 --source-group "${master_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol udp --port 53 --source-group "${account1_worker_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol udp --port 53 --group-owner "${account2_id}" --source-group "${account2_worker_sg_id}"

aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol udp --port 1023 --source-group "${master_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol udp --port 1023 --source-group "${account1_worker_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol udp --port 1023 --group-owner "${account2_id}" --source-group "${account2_worker_sg_id}"

#weavnet
aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol tcp --port 6783 --source-group "${master_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol tcp --port 6783 --source-group "${account1_worker_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol tcp --port 6783 --group-owner "${account2_id}" --source-group "${account2_worker_sg_id}"

aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol udp --port 6783-6784 --source-group "${master_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol udp --port 6783-6784 --source-group "${account1_worker_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${master_sg_id}"  --protocol udp --port 6783-6784 --group-owner "${account2_id}" --source-group "${account2_worker_sg_id}"

#account1 worker security group
aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}" --protocol tcp --port 22 --cidr "${host_public_ip}/32"

#dns ports
aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}"  --protocol tcp --port 53 --source-group "${master_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}"  --protocol tcp --port 53 --source-group "${account1_worker_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}"  --protocol tcp --port 53 --group-owner "${account2_id}" --source-group "${account2_worker_sg_id}"

aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}"  --protocol udp --port 53 --source-group "${master_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}"  --protocol udp --port 53 --source-group "${account1_worker_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}"  --protocol udp --port 53 --group-owner "${account2_id}" --source-group "${account2_worker_sg_id}"

aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}"  --protocol udp --port 1023 --source-group "${master_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}"  --protocol udp --port 1023 --source-group "${account1_worker_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}"  --protocol udp --port 1023 --group-owner "${account2_id}" --source-group "${account2_worker_sg_id}"

#port 10250 used by kubelet
aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}"  --protocol tcp --port 10250  --source-group "${master_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}"  --protocol tcp --port 10250  --source-group "${account1_worker_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}"  --protocol tcp --port 10250  --group-owner "${account2_id}" --source-group "${account2_worker_sg_id}"

#port 30000-32767 for nodeport service type
aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}"  --protocol tcp --port 30000-32767  --source-group "${master_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}"  --protocol tcp --port 30000-32767  --source-group "${account1_worker_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}"  --protocol tcp --port 30000-32767  --group-owner "${account2_id}" --source-group "${account2_worker_sg_id}"

#weavnet
aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}"  --protocol tcp --port 6783 --source-group "${master_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}"  --protocol tcp --port 6783 --source-group "${account1_worker_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}"  --protocol tcp --port 6783 --group-owner "${account2_id}" --source-group "${account2_worker_sg_id}"

aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}"  --protocol udp --port 6783-6784 --source-group "${master_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}"  --protocol udp --port 6783-6784 --source-group "${account1_worker_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account1_worker_sg_id}"  --protocol udp --port 6783-6784 --group-owner "${account2_id}" --source-group "${account2_worker_sg_id}"

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


create_master_node
create_account1_worker_nodes

export AWS_PROFILE=account2

#account2 worker security group
aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}" --protocol tcp --port 22 --cidr "${host_public_ip}/32"

#dns ports
aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}"  --protocol tcp --port 53 --source-group "${master_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}"  --protocol tcp --port 53 --group-owner "${account1_id}" --source-group "${account1_worker_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}"  --protocol tcp --port 53 --source-group "${account2_worker_sg_id}"

aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}"  --protocol udp --port 53 --source-group "${master_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}"  --protocol udp --port 53 --group-owner "${account1_id}"  --source-group "${account1_worker_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}"  --protocol udp --port 53 --source-group "${account2_worker_sg_id}"

aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}"  --protocol udp --port 1023 --source-group "${master_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}"  --protocol udp --port 1023 --group-owner "${account1_id}" --source-group "${account1_worker_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}"  --protocol udp --port 1023 --source-group "${account2_worker_sg_id}"

#port 10250 used by kubelet
aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}"  --protocol tcp --port 10250  --source-group "${master_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}"  --protocol tcp --port 10250  --group-owner "${account1_id}" --source-group "${account1_worker_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}"  --protocol tcp --port 10250  --source-group "${account2_worker_sg_id}"

#port 30000-32767 for nodeport service type
aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}"  --protocol tcp --port 30000-32767  --source-group "${master_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}"  --protocol tcp --port 30000-32767  --group-owner "${account1_id}" --source-group "${account1_worker_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}"  --protocol tcp --port 30000-32767  --source-group "${account2_worker_sg_id}"

#weavnet
aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}"  --protocol tcp --port 6783 --source-group "${master_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}"  --protocol tcp --port 6783 --group-owner "${account1_id}" --source-group "${account1_worker_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}"  --protocol tcp --port 6783 --source-group "${account2_worker_sg_id}"

aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}"  --protocol udp --port 6783-6784 --source-group "${master_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}"  --protocol udp --port 6783-6784 --group-owner "${account1_id}"  --source-group "${account1_worker_sg_id}"
aws ec2 authorize-security-group-ingress --group-id  "${account2_worker_sg_id}"  --protocol udp --port 6783-6784 --source-group "${account2_worker_sg_id}"


cat ec2-instance-specification.json | sed -e "s/key_name/${ec2_key}/" \
                                          -e "s/subnet_id/${account2_worker_subnet_id}/" \
                                          -e "s/sg_id/${account2_worker_sg_id}/" \
                                          -e "s/instance_type/${instance_type}/" \
                                          -e "s/zone/${zone}/" \
                                          -e "s/iam_instance_profile/${account2_iam_instance_profile}/"  > account2-worker-specification.json

aws ec2 delete-key-pair --key-name "${ec2_key}" 
aws ec2 import-key-pair --key-name "${ec2_key}" --public-key-material "fileb://${ec2_key}.pub" 

create_account2_worker_nodes


worker_ips=("${account1_worker_ips[@]}" "${account2_worker_ips[@]}")
join_with_comma "${worker_ips[@]}"
worker_ips_string=$(echo $result_string | sed "s@[']@\"@g")

join_with_comma "${account1_worker_private_ips[@]}"
account1_worker_private_ips_string=$(echo $result_string | sed "s@[']@\"@g")

join_with_comma "${account2_worker_private_ips[@]}"
account2_worker_private_ips_string=$(echo $result_string | sed "s@[']@\"@g")

join_with_comma "${account1_spot_request_ids[@]}"
account1_spot_request_ids_string=$(echo $result_string | sed "s@[']@\"@g")

join_with_comma "${account2_spot_request_ids[@]}"
account2_spot_request_ids_string=$(echo $result_string | sed "s@[']@\"@g")

master_private_ip=$(echo $master_private_ip | sed -e "s/'//g")
master_public_ip=$(echo $master_public_ip | sed -e "s/'//g")

cat "ec2-details-template.json" | sed -e "s/master_public_ip/${master_public_ip}/" \
                             -e "s/master_private_ip/${master_private_ip}/" \
                             -e "s@[\"]worker_ips_string[\"]@${worker_ips_string}@" \
                             -e "s@[\"]account1_worker_private_ips_string[\"]@${account1_worker_private_ips_string}@" \
                             -e "s@[\"]account2_worker_private_ips_string[\"]@${account2_worker_private_ips_string}@" \
                             -e "s@[\"]account1_spot_request_ids_string[\"]@${account1_spot_request_ids_string}@" \
                             -e "s@[\"]account2_spot_request_ids_string[\"]@${account2_spot_request_ids_string}@" > ec2-details.json
