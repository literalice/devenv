#!/bin/bash

set -x

## Params

volume_id=$1
user_id=$2

idms_token=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
instance_id=$(curl -s -H "X-aws-ec2-metadata-token: $idms_token" 169.254.169.254/latest/meta-data/instance-id)
export AWS_DEFAULT_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $idms_token" http://169.254.169.254/latest/meta-data/placement/availability-zone | sed -e 's/.$//')

## Additional Packages
dnf -y install nvme-cli
dnf -y install gcc gcc-c++ make zlib-devel bzip2 bzip2-devel readline-devel sqlite sqlite-devel openssl11-devel tk-devel libffi-devel xz-devel
dnf -y install zsh util-linux-user git

## SSM Plugin
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "session-manager-plugin.rpm"
dnf install -y session-manager-plugin.rpm

### Packer
dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
dnf -y install packer

## Latest
dnf -y upgrade

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
mkfs -t xfs $HOME_DISK

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
useradd -u 1023 -M -d /home/${user_id} --shell=/usr/bin/zsh ${user_id}
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

dnf -y install docker
usermod -aG docker ${user_id}
systemctl start docker
systemctl enable docker

# Compose
wget https://github.com/docker/compose/releases/download/v2.17.3/docker-compose-linux-x86_64
chmod +x docker-compose-linux-x86_64
mv docker-compose-linux-x86_64 /usr/libexec/docker/cli-plugins/docker-compose
