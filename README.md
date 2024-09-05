# DCV-Log-Rotation

The DCV clipboard audit log file will be rotated only with DCV Server restart. The file rotation based on date or size is currently not officialy supported. Those improvements are in the DCV roadmap, in the meantime we would like to offer a workaround using overlayfs to make log rotation possible without restart of the DCV Server. This script uses OverlayFS and a rotate script to accomplish that.

## How to install

```bash
systemctl stop dcvserver
sudo bash installer.sh
systemctl start dcvserver
```

## How to configure:

Edit the file:  /etc/rotate_dcv_logs.conf
```bash
# Set the log directory to the merged overlay
# You can mount it in a specific parition if you want to provide more space 
LOG_DIR="/var/log/dcv_merged"

# Set the max file size in kilobytes to be rotated. When it reaches the size, the rotation will happen
MAX_SIZE_KB=1024

# Set the number of compressed log files to keep (per log type: compressed and not compressed)
KEEP_COMPRESSED=10
```

## How to uninstall

```bash
systemctl stop dcvserver
sudo bash uninstaller.sh
systemctl start dcvserver
```

## About OverlayFS

Imagine OverlayFS as a magical office with three special areas:

* Lower Directory (Read-only Archive): Think of this as a locked filing cabinet full of important documents. You can read these documents, but you can't change them.
* Upper Directory (Writable Workspace): This is like your personal desk where you can put new documents and make changes. Any changes you make or new files you create happen here.
* Merged Directory (The Magic View): This is a special viewing area where you see everything combined. It shows you both the original documents from the filing cabinet and any changes or new documents on your desk.

## How it works

OverlayFS in the DCV context works like this:

The original /var/log/dcv directory becomes the read-only lower layer. A new upper layer is created on a separate, larger partition. These are combined into a merged view that DCV sees as /var/log/dcv. When DCV writes logs, it actually writes to the upper layer. When logs are rotated or truncated, these operations occur in the upper layer. The lower layer remains untouched.

This setup allows for efficient space management:

* Log files can be truncated or deleted in the upper layer, freeing up space on the larger partition.
* The original lower layer stays small and unchanged.
* Even if a log file grows large, it only affects the upper layer's partition.
* Rotation and compression happen in the upper layer, further saving space.

Using OverlayFS and rotate script, we can reduce the logs usage without restart the service:

* Traditional log handling:
When you delete or truncate a log file that's currently being written to by a service, the space isn't immediately released.
The service continues to write to the file descriptor of the deleted file.
The space is only truly freed when the service is restarted, closing the old file descriptor.

* The approach with OverlayFS and rotation scripts:
When rotation script rotates and compresses logs, it's creating new files.
The DCV service writes to these new files immediately, without needing a restart.
Old, rotated logs can be safely deleted, actually freeing up space.
Compressed logs take up less space.
