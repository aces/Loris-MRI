# LORIS Python server

## Installation

This package can be installed with the following command (from the LORIS Python root directory):

```sh
pip install python/loris_server
```

## Deployment

The LORIS Python server can be deployed as a standard Linux service, this can be done using a service file such as `/etc/systemd/system/loris-server.service`, with a content such as the following:

```ini
[Unit]
Description=LORIS Python server
After=network.target

[Service]
User=lorisadmin
Group=lorisadmin
WorkingDirectory=/opt/loris/bin/mri
ExecStart=/bin/bash -c 'source environment && exec run-loris-server'
Restart=always
RestartSec=5
Environment="PYTHONUNBUFFERED=1"

[Install]
WantedBy=multi-user.target
```

The LORIS Python server can then be used as any Linux service with commands such as the following:
- `systemctl start loris-server` to start the server.
- `systemctl stop loris-server` to stop the server.
- `systemctl restart loris-server` to restart the server.
- `journalctl -u loris-server` to view the server logs.
- `journalctl -u loris-server -f` to view the server logs in real-time.
- `journalctl -u loris-server -p err` to view only the server error logs.
