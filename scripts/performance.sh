#!/bin/bash

echo "Current CPU scaling:" $(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | uniq)
sudo bash -c 'echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor' >/dev/null
echo "New CPU scaling:" $(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | uniq)
