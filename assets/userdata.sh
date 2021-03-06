#!/bin/bash

set -x

## Params

volume_id=$1
user_id=$2

instance_id=$(curl -s 169.254.169.254/latest/meta-data/instance-id)
export AWS_DEFAULT_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed -e 's/.$//')


## Systems Manager
sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent

## Additional Packages
yum -y install yum-utils nvme-cli
yum -y install gcc gcc-c++ make zlib-devel bzip2 bzip2-devel readline-devel sqlite sqlite-devel openssl11-devel tk-devel libffi-devel xz-devel
yum -y install zsh util-linux-user git

## AWS CLI
yum remove -y awscli
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

## SSM Plugin
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "session-manager-plugin.rpm"
yum install -y session-manager-plugin.rpm

### Packer
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
yum -y install packer

## Latest
yum -y update

## Disk

## Prepares volumes
while :; do
    aws ec2 wait volume-available --volume-ids $volume_id && break
done;

aws ec2 attach-volume --volume-id $volume_id --instance-id $instance_id --device /dev/xvdb
aws ec2 wait volume-in-use --volume-ids $volume_id

until [ -e /dev/xvdb ]; do
    sleep 1
done

## Format

EPHEMERAL_DISK=$(nvme list | grep 'Amazon EC2 NVMe Instance Storage' | awk '{ print $1 }')
mkfs -t xfs $EPHEMERAL_DISK

HOME_DISK=$(nvme list | grep vol${volume_id#????} | awk '{ print $1 }')
if [ "$(file -b -s $HOME_DISK)" == "data" ]; then
    mkfs -t xfs $HOME_DISK
fi

sleep 1

## Mount

## Ephemeral for docker storage
mkdir -p /var/lib/docker
mount $EPHEMERAL_DISK /var/lib/docker

EPHEMERAL_DISK_UUID=`blkid -o export $EPHEMERAL_DISK | grep UUID`
echo $EPHEMERAL_DISK_UUID /var/lib/docker xfs defaults,nofail 0 2 >> /etc/fstab

## EBS for user home
mkdir -p /home/${user_id}
mount $HOME_DISK /home/${user_id}

HOME_DISK_UUID=`blkid -o export $HOME_DISK | grep UUID`
echo $HOME_DISK_UUID /home/${user_id} xfs defaults,nofail 0 2 >> /etc/fstab

## Sets up home dir
useradd -d /home/${user_id} --shell=/usr/bin/zsh ${user_id}
if [ ! -f "/home/${user_id}/.bash_profile" ]; then
    cp -R /etc/skel/.[a-z]* /home/${user_id}
    mkdir -p /home/${user_id}/.ssh
    cp -n /home/ec2-user/.ssh/authorized_keys /home/${user_id}/.ssh/
    chown -R ${user_id}:${user_id} /home/${user_id}
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

# Compose
wget https://github.com/docker/compose/releases/download/v2.6.1/docker-compose-linux-x86_64
chmod +x docker-compose-linux-x86_64
mv docker-compose-linux-x86_64 /usr/libexec/docker/cli-plugins/docker-compose
