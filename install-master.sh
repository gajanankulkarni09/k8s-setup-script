sudo kubeadm init --config=config.yaml --upload-certs
mkdir -p $HOME/.kube
if [ -f $HOME/.kube/config ]
then
    rm $HOME/.kube/config
fi
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
sudo kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
sudo apt install jq -y