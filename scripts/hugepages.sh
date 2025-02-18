#!/bin/bash

# 2GB of 1GB pages
sudo umount /mnt/huge1GB
sudo bash -c 'echo 2 > /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages'
sudo mkdir -p /mnt/huge1GB
sudo mount -t hugetlbfs -o pagesize=1G none /mnt/huge1GB
sudo chown "${USER}:${USER}" /mnt/huge1GB

# 2GB of 2MB pages
sudo umount /mnt/huge2MB
sudo bash -c 'echo 1024 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages'
sudo mkdir -p /mnt/huge2MB
sudo mount -t hugetlbfs -o pagesize=2M none /mnt/huge2MB
sudo chown "${USER}:${USER}" /mnt/huge2MB
