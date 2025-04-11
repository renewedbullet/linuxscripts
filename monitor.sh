#!/bin/bash

POOL="maun" # pool name
NET_IF="enp42s0" # Adapter name
INTERVAL=2
MAX_DISKS=12    # Max number of disks to show
MAX_ZFS_LINES=25

cleanup() {
  stty echo
  tput rmcup
  tput cnorm
  exit
}
trap cleanup INT TERM

stty -echo
tput smcup
tput civis

while true; do
  START=$(date +%s)
  tput home

  ##### DISK IO
  DISK_IO=$(iostat -xd | awk '
    /^sd[a-z]/ {
      util = $(NF)
      await = $(NF-4)
      color = "\033[1;32m"
      if (util+0 > 80) color="\033[1;31m"
      else if (util+0 > 50) color="\033[1;33m"
      printf "%-8s | %s%6s%%\033[0m | %9s\n", $1, color, util, await
    }')

  DISK_LINES=$(echo "$DISK_IO" | wc -l)
  PADDING_DISK=$((MAX_DISKS - DISK_LINES))

  ##### ZFS
  ZFS_IO=$(zpool iostat -v "$POOL" 1 2 | awk '
    BEGIN { skip=1 }
    /^pool/ { if (skip) { skip=0; next } }
    skip==0 { print }
  ')
  ZFS_LINE_COUNT=$(echo "$ZFS_IO" | wc -l)
  PAD_ZFS=$((MAX_ZFS_LINES - ZFS_LINE_COUNT))

  ##### NETWORK IO
  RX1=$(< /sys/class/net/$NET_IF/statistics/rx_bytes)
  TX1=$(< /sys/class/net/$NET_IF/statistics/tx_bytes)
  sleep 1
  RX2=$(< /sys/class/net/$NET_IF/statistics/rx_bytes)
  TX2=$(< /sys/class/net/$NET_IF/statistics/tx_bytes)
  RX_MB=$(( (RX2 - RX1) / 1024 / 1024 ))
  TX_MB=$(( (TX2 - TX1) / 1024 / 1024 ))

  ##### DRAW SCREEN
  echo -e "\033[1;37m========== Proxmox Monitor ($(date '+%Y-%m-%d %H:%M:%S')) ==========\033[0m"
  echo -e "ZFS Pool: $POOL   |  NIC: $NET_IF   |  Refresh: ${INTERVAL}s\n"

  echo -e "\033[1;36m📀 Disk I/O Utilization (%util / await)\033[0m"
  echo -e "Device   |  %util | await (ms)"
  echo "-------------------------------"
  echo "$DISK_IO"
  for ((i=0; i<PADDING_DISK; i++)); do echo; done

  echo -e "\n\033[1;36m🧠 ZFS Pool Throughput ($POOL)\033[0m"
  echo "$ZFS_IO"
  for ((i=0; i<PAD_ZFS; i++)); do echo; done

  echo -e "\n\033[1;36m🌐 Network Activity ($NET_IF)\033[0m"
  echo -e "RX: \033[1;32m${RX_MB} MiB/s\033[0m | TX: \033[1;34m${TX_MB} MiB/s\033[0m"

  END=$(date +%s)
  RUNTIME=$(( END - START ))
  [ "$RUNTIME" -lt "$INTERVAL" ] && sleep $((INTERVAL - RUNTIME))
done
