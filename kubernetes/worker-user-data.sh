#!/bin/bash

######### ** FOR WORKER NODE ** #########

hostname k8s-worker
echo "k8s-worker" > /etc/hostname

apt update
apt install apt-transport-https ca-certificates curl software-properties-common -y
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"

#Installing Docker
tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter


apt update
apt-cache policy docker-ce
apt install docker-ce -y
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
apt install -y unzip
unzip -qq awscliv2.zip
sudo ./aws/install

rm -rf awscliv2.zip aws/

#Be sure to understand, if you follow official Kubernetes documentation, in Ubuntu 20 it does not work, that is why, I did modification to script
#Adding Kubernetes repositories

#Next 2 lines are different from official Kubernetes guide, but the way Kubernetes describe step does not work
# curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add
# echo "deb https://packages.cloud.google.com/apt kubernetes-xenial main" > /etc/apt/sources.list.d/kurbenetes.list

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list


#Turn off swap
swapoff -a
sudo sed -i '/swap/d' /etc/fstab
mount -a
ufw disable

#Installing Kubernetes tools
apt update
# apt install kubelet kubeadm kubectl -y
apt install -y kubelet kubeadm kubectl


#next line is getting EC2 instance IP, for kubeadm to initiate cluster
#we need to get EC2 internal IP address- default ENI is eth0
export ipaddr=`ip address|grep eth0|grep inet|awk -F ' ' '{print $2}' |awk -F '/' '{print $1}'`


# the kubeadm init won't work entel remove the containerd config and restart it.
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Restart containerd and kubelet
systemctl restart containerd
systemctl restart kubelet

tee /etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system

# to insure the join command start when the installion of master node is done.
# sleep 5m

# aws s3 cp s3://k8s-cluster-config-bucket-karthik/join_command.sh /tmp/.
# chmod +x /tmp/join_command.sh
# bash /tmp/join_command.sh

# Loop to fetch and execute the join command
while true; do
    # Download the join command from S3
    aws s3 cp s3://k8s-cluster-config-bucket-karthik/join_command.sh /tmp/join_command.sh --quiet

    echo "Attempting to join the cluster..."
    chmod +x /tmp/join_command.sh
    bash /tmp/join_command.sh

    # Check if the node successfully joined the cluster
    if [[ $? -eq 0 ]]; then
        echo "Successfully joined the Kubernetes cluster."
        break
    else
        echo "Failed to join the cluster. Retrying in 30 seconds..."
    fi

    # Wait before the next attempt
    sleep 30
done