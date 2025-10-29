#!/bin/bash

# Fetch Toggl time entries for the last N weeks (default: last week + current week) using API and jq
# Usage: ./toggle-data [N]
#   N = number of last weeks to include (default: 1)
#   e.g. N=1: last week + current week, N=2: last 2 weeks + current week, etc.
# Requirements: curl, jq

set -e

# Configurable: if minutes over last 15-min block are less than this, round down
ROUND_DOWN_THRESHOLD_MINUTES=5
# Hardcode API token here or set TOGGL_API_TOKEN environment variable
# TOGGL_API_TOKEN="your_api_token_here"

# internal variables
bold=$(tput bold)
normal=$(tput sgr0)
TEMPDIR=$(mktemp -d)
TEST_DAILY_TOTALS=$(mktemp -p "$TEMPDIR")
DAILY_TOTALS=$(mktemp -p "$TEMPDIR")
TMPFILE=$(mktemp -p "$TEMPDIR")

# Cleanup function to remove temp files
cleanup() {
  rm -rf "$TEMPDIR"
}

# Ensure cleanup runs when the script exits
trap cleanup EXIT SIGINT SIGTERM

# Parse integer argument for number of weeks (default: 1)
if [[ "$1" =~ ^[0-9]+$ ]]; then
  NUM_WEEKS="$1"
else
  NUM_WEEKS=1
fi

if [[ "$1" == "--test" ]]; then
  echo "Running in TEST mode with sample data."
  cat >"$TEST_DAILY_TOTALS" <<EOF
Date	TotalSeconds
2025-09-15	1200   # Mon, week 1
2025-09-16	0      # Tue, week 1
2025-09-17	0      # Wed, week 1
2025-09-18	0      # Thu, week 1
2025-09-19	0      # Fri, week 1
2025-09-20	0      # Sat, week 1
2025-09-21	0      # Sun, week 1
2025-09-22	1800   # Mon, week 2
2025-09-23	0      # Tue, week 2
2025-09-24	0      # Wed, week 2
2025-09-25	0      # Thu, week 2
2025-09-26	0      # Fri, week 2
2025-09-27	0      # Sat, week 2
2025-09-28	0      # Sun, week 2
2025-09-29	0      # Mon, week 3
2025-09-30	0      # Tue, week 3
2025-10-01	3600   # Wed, week 3
2025-10-02	0      # Thu, week 3
2025-10-03	0      # Fri, week 3
2025-10-04	0      # Sat, week 3
2025-10-05	0      # Sun, week 3
2025-10-06	1800   # Mon, week 4
2025-10-07	3599   # Tue, week 4
2025-10-08	3600   # Wed, week 4
2025-10-09	539    # Thu, week 4
2025-10-10	600    # Fri, week 4
2025-10-11	1200   # Sat, week 4
2025-10-12	30900  # Sun, week 4
2025-10-13	1800   # Mon, current week
2025-10-14	0      # Tue, current week
2025-10-15	0      # Wed, current week
2025-10-16	0      # Thu, current week
2025-10-17	0      # Fri, current week
2025-10-18	0      # Sat, current week
2025-10-19	0      # Sun, current week
EOF
  input_file=$TEST_DAILY_TOTALS
else
  # Prompt for API token if not set
  if [ -z "$TOGGL_API_TOKEN" ]; then
    read -rsp "Enter your Toggl API token: " TOGGL_API_TOKEN
    echo
  fi

  # Calculate date ranges for last N full weeks and this week
  TODAY=$(date -u +%Y-%m-%d)
  DOW=$(date -u -d "$TODAY" +%u) # 1=Mon, 7=Sun
  THIS_MONDAY=$(date -u -d "$TODAY -$((DOW - 1)) days" +%Y-%m-%d)
  # Start of N full weeks ago (Monday)
  START_NW_AGO=$(date -u -d "$THIS_MONDAY -$((NUM_WEEKS * 7)) days" +%Y-%m-%d)
  # End of today (for this week)
  END_TODAY=$TODAY

  # Fetch time entries for the whole range
  START_DATE="$START_NW_AGO"
  END_DATE="$END_TODAY"
  START_DATE_API="${START_DATE}T00:00:00Z"
  END_DATE_API="${END_DATE}T23:59:59Z"

  RESPONSE=$(curl -s -u "$TOGGL_API_TOKEN:api_token" \
    -G "https://api.track.toggl.com/api/v9/me/time_entries" \
    --data-urlencode "start_date=$START_DATE_API" \
    --data-urlencode "end_date=$END_DATE_API" \
    -H "Content-Type: application/json")

  echo "$RESPONSE" >"$TMPFILE"

  COUNT=$(jq length "$TMPFILE")
  echo "Fetched $COUNT time entries from $START_DATE_API to $END_DATE_API."
  echo ""

  # Write daily totals for the full range
  echo -e "Date\tTotalSeconds" >"$DAILY_TOTALS"
  current_day="$START_DATE"
  while [[ "$current_day" < "$END_DATE" || "$current_day" == "$END_DATE" ]]; do
    total=$(jq --arg day "$current_day" 'map(select(.start | startswith($day)) | select(.duration > 0) | .duration) | add // 0' "$TMPFILE")
    echo -e "$current_day\t$total" >>"$DAILY_TOTALS"
    current_day=$(date -u -I -d "$current_day + 1 day")
  done

  input_file="$DAILY_TOTALS"
fi

week_counter=0
prev_week=""
week_total=0
week_days=0
week_netvisor_min=0

if [[ "$1" == "--test" ]]; then
  # In test mode, determine week boundaries from test data
  # Get all dates from test data
  mapfile -t all_dates < <(tail -n +2 "$input_file" | cut -f1 | sort)
  earliest_date="${all_dates[0]}"
  latest_date="${all_dates[-1]}"
  # Find Monday before or equal to earliest_date
  earliest_dow=$(date -u -d "$earliest_date" +%u)
  first_monday=$(date -u -d "$earliest_date -$((earliest_dow - 1)) days" +%Y-%m-%d)
  # Find Sunday after or equal to latest_date
  latest_dow=$(date -u -d "$latest_date" +%u)
  last_sunday=$(date -u -d "$latest_date +$((7 - latest_dow)) days" +%Y-%m-%d)
  # Build week_starts and week_ends arrays for NUM_WEEKS full weeks + current week
  week_starts=()
  week_ends=()
  # Find the Monday of the current week in test data
  current_monday=$(date -u -d "$latest_date -$(($(date -u -d "$latest_date" +%u) - 1)) days" +%Y-%m-%d)
  # Add previous NUM_WEEKS full weeks
  for ((i = NUM_WEEKS; i >= 1; i--)); do
    week_starts+=("$(date -u -d "$current_monday -$((i * 7)) days" +%Y-%m-%d)")
  done
  week_starts+=("$current_monday")
  for ((i = NUM_WEEKS; i >= 1; i--)); do
    week_ends+=("$(date -u -d "$current_monday -$((i * 7 - 1)) days" +%Y-%m-%d)")
  done
  week_ends+=("$latest_date")

else
  # Prepare week boundaries for printing
  # Get this Monday and today
  THIS_MONDAY=$(date -u -d "$(date -u +%Y-%m-%d) -$(($(date -u +%u) - 1)) days" +%Y-%m-%d)
  TODAY=$(date -u +%Y-%m-%d)
  # Build array of week starts (N full weeks before this week)
  week_starts=()
  for ((i = NUM_WEEKS; i >= 1; i--)); do
    week_starts+=("$(date -u -d "$THIS_MONDAY -$((i * 7)) days" +%Y-%m-%d)")
  done
  week_starts+=("$THIS_MONDAY")
  # Build array of week ends (Sunday for full weeks, today for this week)
  week_ends=()
  for ((i = NUM_WEEKS; i >= 1; i--)); do
    week_ends+=("$(date -u -d "$THIS_MONDAY -$((i * 7 - 1)) days" +%Y-%m-%d)")
  done
  week_ends+=("$TODAY")

fi

# Read daily totals into associative array
declare -A daily_seconds
while IFS=$'\t' read -r date total _; do
  # Remove comments and whitespace from total
  total=$(echo "$total" | cut -d'#' -f1 | xargs)
  daily_seconds[$date]="$total"
done < <(tail -n +2 "$input_file")

# Print each week
for idx in $(seq 0 $NUM_WEEKS); do
  week_start="${week_starts[$idx]}"
  week_end="${week_ends[$idx]}"
  week_total=0
  week_days=0
  # Print week separator with ISO week number
  week_num=$(date -d "$week_start" +%V)
  # Calculate table width from header
  header="Date\t\tWeekday\tNetvisor\tRaw"
  # For dash line, estimate width using expanded header
  expanded_header=$(echo -e "$header" | expand -t 8)
  table_width=${#expanded_header}
  prefix="Week $week_num  "
  dash_count=$((table_width - ${#prefix}))
  sep_line="$prefix"
  for ((i = 0; i < dash_count; i++)); do sep_line+="-"; done
  echo -e "$sep_line"
  echo -e "$header"
  week_netvisor_min=0
  for offset in {0..6}; do
    current_day=$(date -u -I -d "$week_start + $offset day")
    # For the current week, only print up to today
    if [[ "$week_end" == "$TODAY" && "$current_day" > "$TODAY" ]]; then
      break
    fi
    # For all other weeks, print all 7 days
    total="${daily_seconds[$current_day]:-0}"
    # Get English weekday abbreviation
    weekday=$(LC_TIME=C date -d "$current_day" +%a)
    # Format as HH:MM:SS
    h=$((total / 3600))
    m=$(((total % 3600) / 60))
    s=$((total % 60))
    hms=$(printf "%02d:%02d:%02d" "$h" "$m" "$s")
    # Rounding logic: if minutes over last 15-min block are less than threshold, round down, else round up
    min=$(((total + 59) / 60))
    mod=$((min % 15))
    if ((mod < ROUND_DOWN_THRESHOLD_MINUTES)); then
      rounded_min=$((min - mod))
    else
      rounded_min=$((min + 15 - mod))
    fi
    # Subtract 30 minutes for netvisor, but not below 0
    netvisor_min=$((rounded_min - 30))
    if ((netvisor_min < 0)); then
      netvisor_min=0
    fi
    netvisor_h=$((netvisor_min / 60))
    netvisor_m=$((netvisor_min % 60))
    netvisor_hm=$(printf "%02d:%02d" "$netvisor_h" "$netvisor_m")
    # Skip Sat/Sun if total is zero
    if { [[ "$weekday" == "Sat" || "$weekday" == "Sun" ]] && ((total == 0)); }; then
      : # skip
    else
      echo -e "$current_day\t$weekday\t${bold}$netvisor_hm${normal}\t\t$hms"
    fi
    week_total=$((week_total + total))
    week_days=$((week_days + 1))
    week_netvisor_min=$((week_netvisor_min + netvisor_min))
  done
  # Print weekly summary
  if ((week_days > 0)); then
    week_h=$((week_total / 3600))
    week_m=$(((week_total % 3600) / 60))
    week_s=$((week_total % 60))
    week_hms=$(printf "%02d:%02d:%02d" "$week_h" "$week_m" "$week_s")
    week_netvisor_h=$((week_netvisor_min / 60))
    week_netvisor_m=$((week_netvisor_min % 60))
    week_netvisor_hm=$(printf "%02d:%02d" "$week_netvisor_h" "$week_netvisor_m")
    avg_sec=$((week_total / week_days))
    avg_h=$((avg_sec / 3600))
    avg_m=$(((avg_sec % 3600) / 60))
    avg_s=$((avg_sec % 60))
    avg_hms=$(printf "%02d:%02d:%02d" "$avg_h" "$avg_m" "$avg_s")
    echo -e "\n  \t      \tWEEK Netvisor:\t${bold}$week_netvisor_hm${normal}"
    echo -e "  \t      \tWEEK Raw:\t$week_hms"
  fi
  # No separator after week; week number line is now the only separator
done
