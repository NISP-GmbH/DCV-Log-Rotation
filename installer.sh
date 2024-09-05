#!/bin/bash
################################################################################
# Copyright (C) 2019-2024 NI SP GmbH
# All Rights Reserved
#
# info@ni-sp.com / www.ni-sp.com
#
# We provide the information on an as is basis.
# We provide no warranties, express or implied, related to the
# accuracy, completeness, timeliness, useability, and/or merchantability
# of the data and are not liable for any loss, damage, claim, liability,
# expense, or penalty, or for any direct, indirect, special, secondary,
# incidental, consequential, or exemplary damages or lost profit
# deriving from the use or misuse of this information.
################################################################################

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Check if dcvserver is running
if systemctl is-active --quiet dcvserver; then
    echo "The dcvserver service is currently running."
    echo "Please stop the service manually and then run this installer again."
    echo "You can stop the service with: sudo systemctl stop dcvserver"
    exit 1
fi

# Create the config file

cat << 'EOF' > /etc/rotate_dcv_logs.conf
# Set the log directory to the merged overlay
LOG_DIR="/var/log/dcv_merged"

# Set the max file size in kilobytes to be rotated
MAX_SIZE_KB=1024

# Set the number of compressed log files to keep (per log type)
KEEP_COMPRESSED=10
EOF

# Create rotate_dcv_logs.sh
cat << 'EOF' > /usr/local/bin/rotate_dcv_logs.sh
#!/bin/bash

# Load the configuration
source /etc/rotate_dcv_logs.conf

# Function to rotate a log file
rotate_log() {
    local log_file="$1"
    local owner="$2"
    local group="$3"
    
    # Get current timestamp
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    
    # Check if file exists and is larger than MAX_SIZE_KB
    if [ -f "$log_file" ] && [ $(du -k "$log_file" | cut -f1) -ge $MAX_SIZE_KB ]; then
        cp "$log_file" "${log_file}.$TIMESTAMP"
        : > "$log_file"  # Truncate the file
        chown $owner:$group "$log_file"
        chmod 644 "$log_file"
        echo "Rotated $log_file"
    else
        echo "$log_file does not exist or is smaller than ${MAX_SIZE_KB}KB"
    fi
}

# Function to fix ownership of rotated and compressed files
fix_ownership() {
    local owner="$1"
    local group="$2"
    local file_pattern="$3"
    
    find "$LOG_DIR" -name "$file_pattern" -type f -exec chown $owner:$group {} +
    echo "Fixed ownership for $file_pattern"
}

# Function to safely remove old rotated logs
remove_old_logs() {
    local log_type="$1"
    local keep_count="$2"
    
    if ls ${LOG_DIR}/${log_type}.log.* 1> /dev/null 2>&1; then
        ls -t ${LOG_DIR}/${log_type}.log.* | tail -n +$((keep_count+1)) | xargs -r rm
        echo "Removed old ${log_type} log files"
    else
        echo "No old ${log_type} log files to remove"
    fi
}

# Function to safely remove old compressed logs
remove_old_compressed_logs() {
    local log_type="$1"
    
    if ls ${LOG_DIR}/${log_type}.log.*.gz 1> /dev/null 2>&1; then
        ls -t ${LOG_DIR}/${log_type}.log.*.gz | tail -n +$((KEEP_COMPRESSED+1)) | xargs -r rm
        echo "Removed old compressed ${log_type} log files, keeping last $KEEP_COMPRESSED"
    else
        echo "No old compressed ${log_type} log files to remove"
    fi
}

# Rotate log files
rotate_log "$LOG_DIR/server.log" dcv dcv
rotate_log "$LOG_DIR/sessionlauncher.log" dcv dcv
rotate_log "$LOG_DIR/agent.console.log" dcv dcv
rotate_log "$LOG_DIR/agentlauncher.gdm.log" dcv dcv

# Remove old log files (keep last 5 rotations)
remove_old_logs "server" 5
remove_old_logs "sessionlauncher" 5
remove_old_logs "agent.console" 5
remove_old_logs "agentlauncher.gdm" 5

# Compress rotated logs
find "$LOG_DIR" -name "*.log.*" -type f ! -name "*.gz" -exec gzip {} + 2>/dev/null </dev/null

# Fix ownership of rotated and compressed files
fix_ownership dcv dcv "server.log*"
fix_ownership dcv dcv "sessionlauncher.log*"
fix_ownership dcv dcv "agent.console.log*"
fix_ownership dcv dcv "agentlauncher.gdm.log*"

# Remove old compressed logs (keep last KEEP_COMPRESSED files)
remove_old_compressed_logs "server"
remove_old_compressed_logs "sessionlauncher"
remove_old_compressed_logs "agent.console"
remove_old_compressed_logs "agentlauncher.gdm"
EOF

# Set permissions for rotate_dcv_logs.sh
chmod +x /usr/local/bin/rotate_dcv_logs.sh

# Set up OverlayFS
mkdir -p /var/log/dcv_lower /var/log/dcv_upper /var/log/dcv_work /var/log/dcv_merged
chown dcv:dcv /var/log/dcv_lower /var/log/dcv_upper /var/log/dcv_work /var/log/dcv_merged

# Add OverlayFS mount to /etc/fstab
if ! grep -q "/var/log/dcv_merged" /etc/fstab; then
    echo "overlay /var/log/dcv_merged overlay lowerdir=/var/log/dcv_lower,upperdir=/var/log/dcv_upper,workdir=/var/log/dcv_work 0 0" >> /etc/fstab
fi

# Mount OverlayFS
mount -a

# Move existing logs to OverlayFS
if [ -d "/var/log/dcv" ]
then
    mv /var/log/dcv/* /var/log/dcv_upper/
    rmdir /var/log/dcv
    ln -s /var/log/dcv_merged /var/log/dcv
    chown dcv:dcv /var/log/dcv_merged
    chmod 0750 /var/log/dcv_merged
fi

# Create systemd service for log rotation
cat << EOF > /etc/systemd/system/rotate-dcv-logs.service
[Unit]
Description=Rotate DCV log files
After=dcvserver.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/rotate_dcv_logs.sh
User=dcv
Group=dcv

[Install]
WantedBy=multi-user.target
EOF

# Create systemd timer for log rotation
cat << EOF > /etc/systemd/system/rotate-dcv-logs.timer
[Unit]
Description=Run DCV log rotation every 5 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF

# Enable and start the timer
systemctl enable rotate-dcv-logs.timer
systemctl start rotate-dcv-logs.timer

# Reload systemd to recognize new units
systemctl daemon-reload

echo "Installation complete. DCV log rotation is now set up and will run every 5 minutes."
echo "Please start the dcvserver service manually with: sudo systemctl start dcvserver"
