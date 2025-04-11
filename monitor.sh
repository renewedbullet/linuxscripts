#!/bin/bash

POOL="maun"
NET_IF="enp42s0"
INTERVAL=2

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

  #### Terminal sizing
  ROWS=$(tput lines)
  HEADER_HEIGHT=6
  FOOTER_HEIGHT=4
  AVAILABLE=$((ROWS - HEADER_HEIGHT - FOOTER_HEIGHT))

  DISK_LINES=$((AVAILABLE / 3))
  ZFS_LINES=$((AVAILABLE - DISK_LINES))

  #### Disk I/O
  DISK_IO=$(iostat -xd | awk '
    /^sd[a-z]/ {
      util = $(NF)
      await = $(NF-4)
      color = "\033[1;32m"
      if (util+0 > 80) color="\033[1;31m"
      else if (util+0 > 50) color="\033[1;33m"
      printf "%-8s | %s%6s%%\033[0m | %9s\n", $1, color, util, await
    }' | head -n "$DISK_LINES")
  PAD_DISK=$((DISK_LINES - $(echo "$DISK_IO" | wc -l)))

  #### ZFS I/O (safe final block only)
  ZFS_TMP=$(mktemp)
/usr/sbin/zpool iostat -v "$POOL" 1 2 > "$ZFS_TMP"
  LAST_POOL_LINE=$(grep -n '^pool' "$ZFS_TMP" | tail -n 1 | cut -d: -f1)
  ZFS_IO=$(tail -n +"$LAST_POOL_LINE" "$ZFS_TMP" | head -n "$ZFS_LINES")
  rm -f "$ZFS_TMP"
  PAD_ZFS=$((ZFS_LINES - $(echo "$ZFS_IO" | wc -l)))

  #### Network I/O
  RX1=$(< /sys/class/net/$NET_IF/statistics/rx_bytes)
  TX1=$(< /sys/class/net/$NET_IF/statistics/tx_bytes)
  sleep 1
  RX2=$(< /sys/class/net/$NET_IF/statistics/rx_bytes)
  TX2=$(< /sys/class/net/$NET_IF/statistics/tx_bytes)
  RX_MB=$(( (RX2 - RX1) / 1024 / 1024 ))
  TX_MB=$(( (TX2 - TX1) / 1024 / 1024 ))

  #### === BUILD OUTPUT BUFFER ===
  OUTPUT=""
  OUTPUT+="\033[1;37m========== Proxmox Monitor ($(date '+%Y-%m-%d %H:%M:%S')) ==========\033[0m\n"
  OUTPUT+="ZFS Pool: $POOL   |  NIC: $NET_IF   |  Refresh: ${INTERVAL}s\n\n"

  OUTPUT+="\033[1;36m📀 Disk I/O Utilization (%util / await)\033[0m\n"
  OUTPUT+="Device   |  %util | await (ms)\n"
  OUTPUT+="-------------------------------\n"
  OUTPUT+="$DISK_IO\n"
  for ((i=0; i<PAD_DISK; i++)); do OUTPUT+="\n"; done

  OUTPUT+="\n\033[1;36m🧠 ZFS Pool Throughput ($POOL)\033[0m\n"
  OUTPUT+="$ZFS_IO\n"
  for ((i=0; i<PAD_ZFS; i++)); do OUTPUT+="\n"; done

  OUTPUT+="\n\033[1;36m🌐 Network Activity ($NET_IF)\033[0m\n"
  OUTPUT+="RX: \033[1;32m${RX_MB} MiB/s\033[0m | TX: \033[1;34m${TX_MB} MiB/s\033[0m\n"

  #### === FLUSH ENTIRE SCREEN AT ONCE ===
  clear
  echo -e "$OUTPUT"

  END=$(date +%s)
  RUNTIME=$((END - START))
  [ "$RUNTIME" -lt "$INTERVAL" ] && sleep $((INTERVAL - RUNTIME))
done
