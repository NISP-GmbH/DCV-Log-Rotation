#!/bin/bash

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Check if dcvserver is running
if systemctl is-active --quiet dcvserver; then
    echo "The dcvserver service is currently running."
    echo "Please stop the service manually and then run this uninstaller again."
    echo "You can stop the service with: sudo systemctl stop dcvserver"
    exit 1
fi

echo "Starting uninstallation process..."

# Remove the rotate_dcv_logs.sh script
if [ -f "/usr/local/bin/rotate_dcv_logs.sh" ]
then
    rm /usr/local/bin/rotate_dcv_logs.sh
    rm /etc/rotate_dcv_logs.conf
    echo "Removed /usr/local/bin/rotate_dcv_logs.sh"
fi

# Remove systemd service and timer
systemctl stop rotate-dcv-logs.timer
systemctl disable rotate-dcv-logs.timer
rm -f /etc/systemd/system/rotate-dcv-logs.service
rm -f /etc/systemd/system/rotate-dcv-logs.timer
systemctl daemon-reload
echo "Removed systemd service and timer for log rotation"

# Unmount OverlayFS
if mount | grep -q "/var/log/dcv_merged"; then
    umount /var/log/dcv_merged
    echo "Unmounted OverlayFS from /var/log/dcv_merged"
fi

# Remove OverlayFS entry from /etc/fstab
sed -i '/\/var\/log\/dcv_merged/d' /etc/fstab
echo "Removed OverlayFS entry from /etc/fstab"

# Restore original /var/log/dcv directory
if [ -L "/var/log/dcv" ]; then
    rm /var/log/dcv
    mkdir /var/log/dcv
    chown dcv:dcv /var/log/dcv
    chmod 0750 /var/log/dcv
    echo "Restored original /var/log/dcv directory"
fi

# Move logs back to original location
if [ -d "/var/log/dcv_upper" ]; then
    mv /var/log/dcv_upper/* /var/log/dcv/
    echo "Moved logs back to /var/log/dcv"
fi

# Remove OverlayFS directories
rm -rf /var/log/dcv_lower /var/log/dcv_upper /var/log/dcv_work /var/log/dcv_merged
echo "Removed OverlayFS directories"

echo "Uninstallation complete. The system has been reverted to its original state."
echo "Please start the dcvserver service manually with: sudo systemctl start dcvserver"
