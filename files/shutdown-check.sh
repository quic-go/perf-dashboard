#!/usr/bin/env bash
# Shut the machine down after 10 minutes without any logged-in users.
# Triggered every minute by shutdown-check.timer.

TIMER_FILE=/var/run/shutdown-timer
users=$(w -h | sort -u -k1,1 | wc -l)
now=$(date +%s)

if [ "$users" -gt 0 ]; then
  rm -f "$TIMER_FILE"
else
  if [ -f "$TIMER_FILE" ]; then
    start=$(cat "$TIMER_FILE")
    elapsed=$((now - start))
    echo "Elapsed time since user logout: $elapsed seconds"
    if [ "$elapsed" -ge 600 ]; then
      /usr/sbin/shutdown -P now
    fi
  else
    echo "$now" > "$TIMER_FILE"
  fi
fi
