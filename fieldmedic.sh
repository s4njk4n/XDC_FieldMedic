#!/bin/bash

set -euo pipefail

# Customizable variables
CSV_FILE="nodes.csv"  # Path to the CSV file (format: node_name,username,ip,rpc_url,ntfy1,ntfy2,expiry)
INTERVAL=300  # Interval between checks in seconds (e.g., 300 = 5 minutes)
TIMEOUT=10  # Curl max time in seconds for RPC query
LAG_THRESHOLD=5.0  # Max acceptable response time in seconds
WAIT_AFTER_REBOOT=300  # Time to wait after reboot in seconds (e.g., 300 = 5 minutes)
LOG_FILE="monitor.log"  # Path to the log file
STATE_DIR="state"  # Directory for state files
CONNECTIVITY_URL="http://www.google.com"  # URL for connectivity check
TZ_AEST="Australia/Sydney"  # Timezone for AEST
NTFY_BASE="https://ntfy.sh/"  # Base URL for ntfy.sh
DATE_FMT="%Y-%m-%d %H:%M:%S"  # Date format for logs

# IMPORTANT: For automatic reboots to work:
# 1. Set up SSH key authentication from this server to each remote node (ssh-copy-id user@ip).
# 2. On each remote node, configure passwordless sudo for 'reboot' in /etc/sudoers.d/ (e.g., 'username ALL=(ALL) NOPASSWD: /sbin/reboot').
# Test manually: ssh user@ip sudo reboot (cancel if needed). Without this, reboots will fail due to password prompts.

# Create state directory if it doesn't exist
mkdir -p "$STATE_DIR"

# Function to log messages
log() {
  echo "$(date +"$DATE_FMT") $*" >> "$LOG_FILE"
}

# Function to trim log to last 48 hours
trim_log() {
  cutoff=$(date -d "48 hours ago" +"$DATE_FMT")
  awk -v cutoff="$cutoff" '$1" "$2 >= cutoff' "$LOG_FILE" > temp.log
  mv temp.log "$LOG_FILE"
}

# Function to send ntfy notification
send_ntfy() {
  local msg="$1"
  local topic
  log "Sending notification: $msg to $ntfy1 ${ntfy2:+and $ntfy2}"
  curl -s -d "$msg" "${NTFY_BASE}${ntfy1}" >/dev/null 2>&1
  if [[ -n "$ntfy2" ]]; then
    curl -s -d "$msg" "${NTFY_BASE}${ntfy2}" >/dev/null 2>&1
  fi
}

# Function to check RPC
check_rpc() {
  local rpc_url="$1"
  local curl_opts=""
  if [[ $rpc_url == https* ]]; then
    curl_opts="-k"
  fi
  local curl_output
  local curl_status
  local response
  local time_total

  curl_output=$(curl $curl_opts -s -m "$TIMEOUT" -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' -w "\n%{time_total}" "$rpc_url" 2>&1)
  curl_status=$?

  if [[ $curl_status != 0 ]]; then
    time_total=999.0
    response=""
  else
    time_total=$(tail -n 1 <<<"$curl_output")
    response=$(sed '$ d' <<<"$curl_output")
  fi

  if [[ $curl_status == 0 ]] && [[ $(echo "$time_total < $LAG_THRESHOLD" | bc -l) == 1 ]] && echo "$response" | jq -e '.result' >/dev/null 2>&1 && [[ -z $(echo "$response" | jq -e '.error // empty') ]]; then
    return 0  # Good
  else
    return 1  # Bad
  fi
}

# Main loop
while true; do
  log "Starting monitoring loop"

  # Check connectivity
  curl -s --head --request GET "$CONNECTIVITY_URL" >/dev/null 2>&1
  if [[ $? != 0 ]]; then
    log "No internet connectivity, skipping this loop"
    sleep 60
    continue
  fi

  trim_log

  tail -n +2 "$CSV_FILE" | while IFS=',' read -r name user ip rpc_url ntfy1 ntfy2 expiry; do
    [[ -z "$name" ]] && continue

    local current_date
    current_date=$(date +%Y-%m-%d)
    if [[ "$current_date" > "$expiry" ]]; then
      log "Node $name monitoring expired ($expiry)"
      continue
    fi

    log "Checking node $name ($ip, $rpc_url)"

    local attempts_file="${STATE_DIR}/${name}.attempts"
    local excluded_file="${STATE_DIR}/${name}.excluded"
    local last_daily_file="${STATE_DIR}/${name}.last_daily"

    local excluded
    excluded=$(cat "$excluded_file" 2>/dev/null || echo 0)

    # Perform RPC check
    local is_good=0
    if check_rpc "$rpc_url"; then
      is_good=1
    fi

    log "Node $name check result: good=$is_good"

    if [[ $is_good == 1 ]]; then
      echo 0 > "$attempts_file"

      # Check for daily notification
      local tz_aest_day
      local tz_aest_hour
      tz_aest_day=$(TZ="$TZ_AEST" date +%Y-%m-%d)
      tz_aest_hour=$(TZ="$TZ_AEST" date +%H)
      local last_daily
      last_daily=$(cat "$last_daily_file" 2>/dev/null || echo "1970-01-01")

      if [[ "$tz_aest_day" > "$last_daily" && "${tz_aest_hour#0}" -ge 8 ]]; then
        send_ntfy "Daily check: $name is functioning fine"
        echo "$tz_aest_day" > "$last_daily_file"
      fi

      if [[ $excluded == 1 ]]; then
        send_ntfy "$name is back to normal"
        echo 0 > "$excluded_file"
      fi
    else
      if [[ $excluded == 1 ]]; then
        log "Node $name still erroring but excluded from remediation"
        continue
      fi

      # Start fresh remediation for this incident
      echo 0 > "$attempts_file"
      local fixed=0
      for ((try=0; try<3; try++)); do
        send_ntfy "Error detected on $name: RPC not responding correctly. Attempting reboot $((try+1))/3."
        log "Rebooting $name ($ip)"
        ssh -o ConnectTimeout=10 "$user"@"$ip" sudo reboot || log "Reboot command failed for $name"

        log "Waiting $WAIT_AFTER_REBOOT seconds for $name to reboot"
        sleep "$WAIT_AFTER_REBOOT"

        # Check again
        if check_rpc "$rpc_url"; then
          send_ntfy "Reboot $((try+1)) fixed the issue on $name."
          fixed=1
          break
        else
          send_ntfy "Reboot $((try+1)) did not fix the issue on $name, still erroring."
        fi
      done

      if [[ $fixed == 0 ]]; then
        send_ntfy "Automated remediation failed for $name after 3 attempts. Manual intervention needed."
        echo 1 > "$excluded_file"
      else
        echo 0 > "$attempts_file"
      fi
    fi
  done

  log "End of monitoring loop, sleeping for $INTERVAL seconds"
  sleep "$INTERVAL"
done
