#!/bin/bash

# Configuration
BASE_PATH="/root/bbb/data/bigbluebutton"
PUBLISHED_PATH="${BASE_PATH}/published/presentation"
UNPUBLISHED_PATH="${BASE_PATH}/unpublished/presentation"
BBB_BASE_URL="https://www.example-bbb.com/playback/presentation/2.3"

# Limits and settings
MAX_CONCURRENT=3
MAX_RETRIES=3
DOCKER_IMAGE="manishkatyan/bbb-mp4"

# Files for tracking
LOG_FILE="/var/log/bbb-mp4-automation.log"
QUEUE_FILE="/var/run/bbb-mp4-queue.txt"
RETRY_FILE="/var/run/bbb-mp4-retries.txt"
MONITOR_PIDS_FILE="/var/run/bbb-mp4-monitors.txt"

# Resource limits
DOCKER_CPU_LIMIT="2.0"
DOCKER_MEMORY_LIMIT="4g"

# Initialize files
touch "$QUEUE_FILE" "$RETRY_FILE" "$MONITOR_PIDS_FILE"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Queue management functions
enqueue() {
    local meeting_path="$1"
    if ! grep -q "^${meeting_path}$" "$QUEUE_FILE"; then
        echo "$meeting_path" >> "$QUEUE_FILE"
        log_message "Added to queue: $meeting_path"
    fi
}

dequeue() {
    if [ ! -s "$QUEUE_FILE" ]; then
        echo ""
        return
    fi
    local first_item=$(head -n 1 "$QUEUE_FILE")
    sed -i '1d' "$QUEUE_FILE"
    echo "$first_item"
}

get_queue_length() {
    if [ -f "$QUEUE_FILE" ]; then
        wc -l < "$QUEUE_FILE"
    else
        echo 0
    fi
}

# Retry management
get_retry_count() {
    local meeting_id="$1"
    grep "^${meeting_id}:" "$RETRY_FILE" 2>/dev/null | cut -d: -f2 || echo 0
}

increment_retry_count() {
    local meeting_id="$1"
    local current_count=$(get_retry_count "$meeting_id")
    local new_count=$((current_count + 1))

    # Remove old entry if exists
    sed -i "/^${meeting_id}:/d" "$RETRY_FILE"
    # Add new count
    echo "${meeting_id}:${new_count}" >> "$RETRY_FILE"
    echo $new_count
}

reset_retry_count() {
    local meeting_id="$1"
    sed -i "/^${meeting_id}:/d" "$RETRY_FILE"
}

# Check concurrent containers
get_running_count() {
    docker ps --filter "ancestor=${DOCKER_IMAGE}" --format '{{.Names}}' | wc -l
}

# Check if MP4 exists and handle accordingly
check_and_handle_mp4() {
    local meeting_path="$1"
    local meeting_id=$(basename "$meeting_path")
    local mp4_main="${meeting_path}/${meeting_id}.mp4"
    local mp4_temp="${meeting_path}/temp/${meeting_id}.mp4"

    # Check if MP4 exists in main folder
    if [ -f "$mp4_main" ]; then
        log_message "MP4 already exists in main folder for meeting: $meeting_id, skipping..."
        reset_retry_count "$meeting_id"
        return 0  # Skip - already done
    fi

    # Check if MP4 exists in temp folder
    if [ -f "$mp4_temp" ]; then
        log_message "MP4 found in temp folder for meeting: $meeting_id, moving to main folder..."
        mv "$mp4_temp" "$mp4_main"
        if [ $? -eq 0 ]; then
            log_message "Successfully moved MP4 from temp to main folder for meeting: $meeting_id"
            # Cleanup temp directory
            rm -rf "${meeting_path}/temp"
            reset_retry_count "$meeting_id"
            return 0  # Skip - just moved
        else
            log_message "ERROR: Failed to move MP4 from temp to main folder for meeting: $meeting_id"
            return 2  # Error moving
        fi
    fi

    return 1  # Neither exists - need to generate
}

# Monitor individual container completion
monitor_container_completion() {
    local container_name="$1"
    local meeting_path="$2"

    # Start background process to wait for container
    (
        # Wait for container to finish
        docker wait "$container_name" > /dev/null 2>&1
        local exit_code=$?

        log_message "Container finished: $container_name (exit code: $exit_code)"

        # Process the completion immediately
        if [ -d "$meeting_path" ]; then
            local meeting_id=$(basename "$meeting_path")
            local mp4_main="${meeting_path}/${meeting_id}.mp4"
            local mp4_temp="${meeting_path}/temp/${meeting_id}.mp4"

            # Wait a moment for file to be fully written
            sleep 2

            # Check if MP4 was generated in temp folder
            if [ -f "$mp4_temp" ]; then
                mv "$mp4_temp" "$mp4_main"
                if [ $? -eq 0 ]; then
                    log_message "Successfully completed and moved MP4 for meeting: $container_name"
                    reset_retry_count "$container_name"
                    # Cleanup temp directory
                    rm -rf "${meeting_path}/temp"
                else
                    log_message "ERROR: Failed to move MP4 for meeting: $container_name"
                fi
            else
                log_message "WARNING: No MP4 file found in temp for meeting: $container_name"
                # Retry the conversion
                local retry_count=$(increment_retry_count "$container_name")
                if [ $retry_count -lt $MAX_RETRIES ]; then
                    log_message "Requeueing meeting for retry: $container_name"
                    enqueue "$meeting_path"
                else
                    log_message "Max retries reached for meeting: $container_name, giving up"
                fi
            fi
        fi

        # Remove this monitor PID from tracking file
        sed -i "/^${container_name}:/d" "$MONITOR_PIDS_FILE"

        # Trigger queue processing
        process_queue
    ) &

    local monitor_pid=$!
    echo "${container_name}:${monitor_pid}" >> "$MONITOR_PIDS_FILE"
    log_message "Started completion monitor for $container_name (PID: $monitor_pid)"
}

# Main processing function
process_meeting() {
    local meeting_path="$1"
    local meeting_id=$(basename "$meeting_path")

    # Check if MP4 exists and handle accordingly
    check_and_handle_mp4 "$meeting_path"
    local check_result=$?

    if [ $check_result -eq 0 ]; then
        # MP4 exists or was moved - skip generation
        return 0
    fi

    # MP4 doesn't exist - need to generate

    # Check if container is already running
    if docker ps --format '{{.Names}}' | grep -q "^${meeting_id}$"; then
        log_message "Container already running for meeting: $meeting_id, skipping..."
        return 0
    fi

    # Check concurrent limit
    local running_count=$(get_running_count)
    if [ $running_count -ge $MAX_CONCURRENT ]; then
        log_message "Max concurrent containers ($MAX_CONCURRENT) reached, queueing meeting: $meeting_id"
        enqueue "$meeting_path"
        return 0
    fi

    # Check retry limit
    local retry_count=$(get_retry_count "$meeting_id")
    if [ $retry_count -ge $MAX_RETRIES ]; then
        log_message "Max retries ($MAX_RETRIES) reached for meeting: $meeting_id, giving up..."
        return 1
    fi

    # Create temp directory if it doesn't exist
    mkdir -p "${meeting_path}/temp"

    log_message "Starting MP4 generation for meeting: $meeting_id (attempt $((retry_count + 1)))"

    # Run the Docker container with resource limits
    docker run --rm -d \
        --name "${meeting_id}" \
        --cpus="${DOCKER_CPU_LIMIT}" \
        --memory="${DOCKER_MEMORY_LIMIT}" \
        -v "${meeting_path}/temp:/usr/src/app/processed" \
        --env REC_URL="${BBB_BASE_URL}/${meeting_id}" \
        "${DOCKER_IMAGE}"

    if [ $? -eq 0 ]; then
        log_message "Successfully started container for meeting: $meeting_id"
        # Start individual monitor for this container
        monitor_container_completion "$meeting_id" "$meeting_path"
        return 0
    else
        log_message "ERROR: Failed to start container for meeting: $meeting_id"
        increment_retry_count "$meeting_id"
        enqueue "$meeting_path"
        return 1
    fi
}

# Process queue
process_queue() {
    local running_count=$(get_running_count)

    while [ $running_count -lt $MAX_CONCURRENT ]; do
        local meeting_path=$(dequeue)
        if [ -z "$meeting_path" ]; then
            break
        fi

        if [ -d "$meeting_path" ]; then
            process_meeting "$meeting_path"
        fi

        running_count=$(get_running_count)
    done
}

# Cleanup function for graceful shutdown
cleanup() {
    log_message "Received shutdown signal, cleaning up..."

    # Kill all monitor processes
    if [ -f "$MONITOR_PIDS_FILE" ]; then
        while IFS=: read -r container_name pid; do
            if [ -n "$pid" ]; then
                kill "$pid" 2>/dev/null || true
            fi
        done < "$MONITOR_PIDS_FILE"
    fi

    # Stop other background processes
    jobs -p | xargs -r kill 2>/dev/null

    log_message "Shutdown complete"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Main execution
log_message "=== BBB MP4 Automation Started ==="
log_message "Max concurrent containers: $MAX_CONCURRENT"
log_message "Docker image: $DOCKER_IMAGE"
log_message "CPU limit: $DOCKER_CPU_LIMIT, Memory limit: $DOCKER_MEMORY_LIMIT"

# Initial scan of existing directories
log_message "Starting initial scan of existing directories..."
for dir_path in "$PUBLISHED_PATH" "$UNPUBLISHED_PATH"; do
    if [ -d "$dir_path" ]; then
        for meeting_dir in "$dir_path"/*; do
            if [ -d "$meeting_dir" ]; then
                enqueue "$meeting_dir"
            fi
        done
    fi
done

# Process initial queue
log_message "Processing initial queue ($(get_queue_length) items)..."
process_queue

# Monitor both directories for new folder creation
log_message "Starting directory monitoring..."
inotifywait -m -e create --format '%w%f' "$PUBLISHED_PATH" "$UNPUBLISHED_PATH" 2>/dev/null | while read new_path
do
    # Only process if it's a directory
    if [ -d "$new_path" ]; then
        log_message "New directory detected: $new_path"
        # Wait a bit to ensure the directory is fully created
        sleep 5

        # Add to queue
        enqueue "$new_path"

        # Try to process queue
        process_queue
    fi
done &
INOTIFY_PID=$!

# Keep script running
log_message "All monitors started. Press Ctrl+C to stop."
wait
