#!/bin/bash

datetime=$(date "+%Y-%m-%d %H:%M:%S")
logfile=/var/log/sys-monitoring.log
BACKUPS=tar -czf "/tmp/log-backup-$(date '+%Y-%m-%d').tar.gz" /var/log/*



iface=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE 'lo|docker|veth' | head -n 1)
rbits=$(awk -v iface="$iface" '$1 ~ iface {print $2}' /proc/net/dev)
sbits=$(awk -v iface="$iface" '$1 ~ iface {print $10}' /proc/net/dev)

hostname=$(hostname)
os=$(lsb_release -d | cut -f2-)
cpu=0 mem=0 disk=0
CPU_THRESHOLD=80.0
MEMORY_THRESHOLD=80.0
DISK_THRESHOLD=80
DISK_CRITICAL=90

cpu_monitoring(){
cpu=$(top -bn1 | grep "Cpu(s)" | awk -F',' '{print 100 - $4}' | awk '{print $1}')
if (( $(echo "$cpu > $CPU_THRESHOLD" | bc -l) )); then
    echo "WARNING: CPU usage is above $CPU_THRESHOLD%. Current usage: $cpu%" | tee -a $logfile
    echo "Top five CPU-consuming processes: " >> $logfile
    ps -eo pid,ppid,cmd,%cpu --sort=-%cpu | head -6 >> $logfile
fi
}

mem_monitoring(){
mem=$(free | awk '/Mem:/ {printf "%.2f", $3/$2 * 100}')
if (( $(echo "$mem > $MEMORY_THRESHOLD" | bc -l) )); then
    echo "WARNING: Memory usage is above $MEMORY_THRESHOLD%. Current usage: $mem%" | tee -a $logfile
    echo "Top 5 Memory-consuming processes: " >> $logfile
    ps -eo pid,ppid,cmd,%mem --sort=-%mem | head -6 >> $logfile 
fi
}

disk_monitoring(){
disk=$(df / | awk 'NR==2 {print $5}' | sed 's/%//g')
if (( $disk > $DISK_THRESHOLD )); then
    echo "WARNING: Disk usage is above $DISK_THRESHOLD%. Current usage: $disk%" | tee -a $logfile
    echo "Creating backup of logs to $BACKUPS" | tee -a $logfile
    mkdir -p $BACKUPS
    cp -r /var/log/* $BACKUPS/
    echo "Backup completed." | tee -a $logfile
fi

if (($disk > $DISK_CRITICAL )); then
echo "CRITICAL ALARM: Disk usage is extremely high. Deleting logs older than a week..." | tee -a $logfile
find /var/log -type f -mtime +7 -exec rm -f {} \;
echo "Old logs deleted successfully." | tee -a $logfile
fi
}

cpu_monitoring
mem_monitoring
disk_monitoring

report="         ========================REPORT====================
         -----------------$datetime-------------
         ================================================
         Hostname: $hostname | OS Version: $os
         ------------------------------------------------
          CPU: $cpu% |  Memory: $mem% |  Disk: $disk%
          Network in: $rbits  |  Network out: $sbits
         ================================================"

echo "$report" | tee -a $logfile
echo "Monitoring finished at $datetime" >> $logfile
