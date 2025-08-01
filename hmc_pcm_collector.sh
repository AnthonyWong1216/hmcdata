#!/bin/ksh

# IBM HMC PCM Data Collector
# Collects PCM data every 5 seconds using REST API and outputs in CSV format

set -e

# Configuration
HMC_HOST="192.168.136.104"  # Change this to your HMC IP
HMC_PORT="12443"           # Default HMC REST API port
LOGIN_XML="login.xml"
OUTPUT_FILE="pcm_data.csv"
INTERVAL=5                  # Data collection interval in seconds

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to log messages
log() {
    print -u2 "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    print -u2 "${RED}[ERROR]${NC} $1"
}

warn() {
    print -u2 "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if curl is available
check_curl() {
    if ! whence curl >/dev/null 2>&1; then
        error "curl is not installed. Please install curl first."
        exit 1
    fi
}

# Function to extract value using sed (ksh compatible)
extract_value() {
    local pattern="$1"
    local data="$2"
    echo "$data" | sed -n "s/.*$pattern//p" | sed 's/["'"'"'"]//g'
}

# Function to authenticate with HMC
authenticate() {
    log "Authenticating with HMC at ${HMC_HOST}:${HMC_PORT}..."
    
    # Create session and get session ID
    SESSION_RESPONSE=$(curl -s -k -X POST \
        -H "Content-Type: application/vnd.ibm.powervm.web+xml; type=LogonRequest" \
        -H "Accept: application/vnd.ibm.powervm.web+xml; type=LogonResponse" \
        -d @${LOGIN_XML} \
        "https://${HMC_HOST}:${HMC_PORT}/rest/api/web/Logon")
    
    if [ $? -ne 0 ]; then
        error "Failed to connect to HMC. Check host and port."
        exit 1
    fi
    
    # Extract session ID from response using sed
    SESSION_ID=$(extract_value 'sessionID="' "$SESSION_RESPONSE")
    
    if [ -z "$SESSION_ID" ]; then
        error "Authentication failed. Check credentials in ${LOGIN_XML}"
        print "Response: $SESSION_RESPONSE"
        exit 1
    fi
    
    log "Authentication successful. Session ID: ${SESSION_ID}"
    echo "$SESSION_ID"
}

# Function to get managed systems
get_managed_systems() {
    local session_id="$1"
    
    log "Getting managed systems..."
    
    SYSTEMS_RESPONSE=$(curl -s -k -X GET \
        -H "X-API-Session: ${session_id}" \
        -H "Accept: application/vnd.ibm.powervm.web+xml; type=ManagedSystemList" \
        "https://${HMC_HOST}:${HMC_PORT}/rest/api/uom/ManagedSystem")
    
    if [ $? -ne 0 ]; then
        error "Failed to get managed systems"
        return 1
    fi
    
    # Extract system IDs using sed
    echo "$SYSTEMS_RESPONSE" | sed -n 's/.*href="[^"]*ManagedSystem\/\([^"]*\)".*/\1/p'
}

# Function to get PCM data for a system
get_pcm_data() {
    local session_id="$1"
    local system_id="$2"
    
    log "Collecting PCM data for system: ${system_id}"
    
    PCM_RESPONSE=$(curl -s -k -X GET \
        -H "X-API-Session: ${session_id}" \
        -H "Accept: application/vnd.ibm.powervm.web+xml; type=PerformanceAndCapacityMonitoring" \
        "https://${HMC_HOST}:${HMC_PORT}/rest/api/uom/ManagedSystem/${system_id}/PerformanceAndCapacityMonitoring")
    
    if [ $? -ne 0 ]; then
        warn "Failed to get PCM data for system ${system_id}"
        return 1
    fi
    
    echo "$PCM_RESPONSE"
}

# Function to parse PCM data and convert to CSV
parse_pcm_to_csv() {
    local pcm_data="$1"
    local system_id="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Extract various PCM metrics using sed
    # CPU utilization
    CPU_UTIL=$(extract_value 'cpuUtilization="' "$pcm_data")
    if [ -z "$CPU_UTIL" ]; then CPU_UTIL="N/A"; fi
    
    # Memory utilization
    MEM_UTIL=$(extract_value 'memoryUtilization="' "$pcm_data")
    if [ -z "$MEM_UTIL" ]; then MEM_UTIL="N/A"; fi
    
    # Network utilization
    NET_UTIL=$(extract_value 'networkUtilization="' "$pcm_data")
    if [ -z "$NET_UTIL" ]; then NET_UTIL="N/A"; fi
    
    # Storage utilization
    STORAGE_UTIL=$(extract_value 'storageUtilization="' "$pcm_data")
    if [ -z "$STORAGE_UTIL" ]; then STORAGE_UTIL="N/A"; fi
    
    # Power consumption
    POWER=$(extract_value 'powerConsumption="' "$pcm_data")
    if [ -z "$POWER" ]; then POWER="N/A"; fi
    
    # Temperature
    TEMP=$(extract_value 'temperature="' "$pcm_data")
    if [ -z "$TEMP" ]; then TEMP="N/A"; fi
    
    # Output CSV format
    echo "${timestamp},${system_id},${CPU_UTIL},${MEM_UTIL},${NET_UTIL},${STORAGE_UTIL},${POWER},${TEMP}"
}

# Function to create CSV header
create_csv_header() {
    echo "Timestamp,System_ID,CPU_Utilization,Memory_Utilization,Network_Utilization,Storage_Utilization,Power_Consumption,Temperature" > "$OUTPUT_FILE"
    log "CSV file created: ${OUTPUT_FILE}"
}

# Function to cleanup session
cleanup_session() {
    local session_id="$1"
    
    if [ -n "$session_id" ]; then
        log "Logging out from HMC..."
        curl -s -k -X POST \
            -H "X-API-Session: ${session_id}" \
            -H "Content-Type: application/vnd.ibm.powervm.web+xml; type=LogoffRequest" \
            "https://${HMC_HOST}:${HMC_PORT}/rest/api/web/Logoff" > /dev/null
    fi
}

# Function to handle script interruption
cleanup() {
    log "Script interrupted. Cleaning up..."
    cleanup_session "$SESSION_ID"
    exit 0
}

# Main execution
main() {
    log "Starting IBM HMC PCM Data Collector"
    log "HMC Host: ${HMC_HOST}:${HMC_PORT}"
    log "Collection interval: ${INTERVAL} seconds"
    log "Output file: ${OUTPUT_FILE}"
    
    # Check prerequisites
    check_curl
    
    if [ ! -f "$LOGIN_XML" ]; then
        error "Login XML file not found: ${LOGIN_XML}"
        exit 1
    fi
    
    # Create CSV header
    create_csv_header
    
    # Set up signal handling
    trap cleanup INT TERM
    
    # Authenticate
    SESSION_ID=$(authenticate)
    
    # Get managed systems
    SYSTEMS=$(get_managed_systems "$SESSION_ID")
    
    if [ -z "$SYSTEMS" ]; then
        error "No managed systems found"
        cleanup_session "$SESSION_ID"
        exit 1
    fi
    
    log "Found managed systems: $(echo "$SYSTEMS" | tr '\n' ' ')"
    
    # Main collection loop
    while true; do
        log "Collecting PCM data..."
        
        for system in $SYSTEMS; do
            PCM_DATA=$(get_pcm_data "$SESSION_ID" "$system")
            
            if [ $? -eq 0 ]; then
                CSV_LINE=$(parse_pcm_to_csv "$PCM_DATA" "$system")
                echo "$CSV_LINE" >> "$OUTPUT_FILE"
                log "Data collected for system: ${system}"
            else
                warn "Failed to collect data for system: ${system}"
            fi
        done
        
        log "Waiting ${INTERVAL} seconds before next collection..."
        sleep "$INTERVAL"
    done
}

main "$@" 