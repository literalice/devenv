#!/bin/bash

set -x

sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent

volume_id=$1
user_id=$2

instance_id=$(curl -s 169.254.169.254/latest/meta-data/instance-id)
export AWS_DEFAULT_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed -e 's/.$//')

## Ephemeral
mkfs -t xfs /dev/nvme1n1
mkdir -p /var/lib/docker
mount /dev/nvme1n1 /var/lib/docker

## Prepares a volume for home dir
while :; do
    aws ec2 wait volume-available --volume-ids $volume_id && break
done;

aws ec2 attach-volume --volume-id $volume_id --instance-id $instance_id --device /dev/xvdb
aws ec2 wait volume-in-use --volume-ids $volume_id

until [ -e /dev/xvdb ]; do
    sleep 1
done

if [ "$(file -b -s /dev/xvdb)" == "data" ]; then
    mkfs -t xfs /dev/xvdb
fi

sleep 1

mkdir -p /home/${user_id}
mount /dev/xvdb /home/${user_id}

## Sets up home dir
useradd -d /home/${user_id} ${user_id}
if [ ! -f "/home/${user_id}/.bash_profile" ]; then
    cp -R /etc/skel/.[a-z]* /home/${user_id}
    mkdir -p /home/${user_id}/.ssh
    cp -n /home/ec2-user/.ssh/authorized_keys /home/${user_id}/.ssh/
    chown -R ${user_id}:${user_id} /home/${user_id}
    echo "alias aws='docker run --rm -it -v ~/.aws:/root/.aws -v \$(pwd):/aws amazon/aws-cli:2.4.10'" >> /home/${user_id}/.bashrc
fi

## Permissions
usermod -aG wheel ${user_id}
echo "${user_id} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${user_id}

## Others
ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime

amazon-linux-extras install -y docker
usermod -aG docker ${user_id}
systemctl start docker
systemctl enable docker
