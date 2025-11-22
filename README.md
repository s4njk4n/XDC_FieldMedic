_Under construction_

# XDC FieldMedic

![XDC FieldMedic Banner](XDC_FieldMedic.jpg)

This Bash script that keeps an eye on XDC masternode RPC endpoints. It pings them regularly, spots if something's off (eg. errors or too much lag) and then SSHes in to reboot the server if needed. Sends notifications via ntfy.sh to 2 channels as well so whoever needs to know is in the loop. I built it to cut down on manual babysitting for my nodes, and figured others might find it handy. Still tweaking it, so follow me [@s4njk4n](https://x.com/s4njk4n) on X if you want updates.

## What It Does

XDC FieldMedic reads a CSV list of your nodes, checks their RPCs every few minutes (you set the interval), and if one's acting up, it tries rebooting the server up to 3 times. After each reboot, it waits a bit and checks again. If it fixes it, great! It then sends a "fixed" note. If not, it flags it for manual fix and stops trying. Also does daily "all good" pings at 8 AM AEST and logs everything. Logs are trimmed of old information after 48 hours.

## Features

- Checks RPC for errors or lag at set intervals.
- Auto-reboots remote server (up to 3 tries) and verifies if it worked.
- Notifies via 1 or 2 ntfy topics per node (errors, fixes, failures, daily "all good" health ping).
- Logs with timestamps, auto-trimmed to 48 hours to avoid chewing up the whole drive with logs.
- Easy tweaks (all vars up top in the script).

## Things You Need

- A VPS running Ubuntu
- curl, jq, bc, ssh, awk
- SSH keys set up for passwordless access to each node (ssh-keygen + ssh-copy-id).
- On remote nodes: sudo reboot without password for the user (add to /etc/sudoers.d/ like `user ALL=(ALL) NOPASSWD: /sbin/reboot` by using visudo).
- ntfy.sh topics ready for alerts.

Quick test: From your monitoring server, try `ssh user@ip sudo reboot` (It should work without prompts (don't actually reboot if it's production node though obviously)).

## Setting It Up On Your VPS

1. Clone the repo:
```
   git clone https://github.com/s4njk4n/XDC_FieldMedic.git
   cd XDC_FieldMedic
```

2. Make the script executable:
```
   chmod +x fieldmedic.sh
```

3. Install dependencies:
```
   sudo apt update && sudo apt install curl jq bc openssh-client gawk 
```

## Tweaking It

### Script Variables

Open `fieldmedic.sh` in nano and you can alter the variables at the top of the script:

- `CSV_FILE="nodes.csv"` – where your node list lives.
- `INTERVAL=300` – seconds between checks (5 mins default).
- `TIMEOUT=10` – how long to wait for RPC response.
- `LAG_THRESHOLD=5.0` – if slower than this, it's laggy.
- `WAIT_AFTER_REBOOT=300` – wait time post-reboot.
- `LOG_FILE="monitor.log"` – log file.
- Etc.

### Your Nodes CSV

Make a `nodes.csv` like this (headers included):
```
node_name,username,ip,rpc_url,ntfy1,ntfy2,expiry
node1,user1,192.168.1.100,http://192.168.1.100:8989,ntfy_topic1,ntfy_topic2,2026-12-31
node2,user2,10.0.0.5,https://rpc.example.com:443,ntfy_topic3,,2025-11-30
node3,user3,172.16.0.10,http://172.16.0.10:8545,ntfy_topic1,ntfy_topic4,2027-01-15
```

- node_name: Whatever you want the node to be called in your ntfy notifications.
- username: For SSH reboot.
- ip: For SSH reboot.
- rpc_url: Full URL to ping (http/https + port).
- ntfy1/ntfy2: Notification channels (if only wanting to use one notification channel, then leave ntfy2 blank).
- expiry: YYYY-MM-DD when to stop watching.

## Running It

Run as a background process:
```
nohup ./fieldmedic.sh &
```

Or use screen/tmux to keep it alive.

Watch logs: `tail -f monitor.log`

Kill it: `ps aux | grep fieldmedic.sh` then `kill <pid>`.

## If It Breaks

- Reboot not working? Double-check SSH/sudo setup; logs will say "Reboot command failed".
- No notifications? Topics wrong or no net—test curl to ntfy.
- RPC checks flop? jq installed? Try curling the URL yourself.
- Expiry weird? Stick to YYYY-MM-DD.

## License

MIT (do what you want, but if you improve it, share back?).

## Stay in contact

Follow [@s4njk4n](https://x.com/s4njk4n) on X for updates and questions.
