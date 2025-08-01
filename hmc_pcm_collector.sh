#!/bin/ksh

# IBM HMC PCM Data Collector (ksh, HMC REST API v2)
# Collects PCM data every 5 seconds using REST API and outputs in CSV format

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function definitions
log() {
    print -u2 "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    print -u2 "${RED}[ERROR]${NC} $1"
}

warn() {
    print -u2 "${YELLOW}[WARNING]${NC} $1"
}

# Source configuration file if it exists
if [ -f "hmc_config.sh" ]; then
    . ./hmc_config.sh
    log "Configuration loaded from hmc_config.sh"
else
    log "Using default configuration (hmc_config.sh not found)"
fi

# Configuration (use config file values or defaults)
HMC_HOST="${HMC_HOST:-192.168.136.104}"  # Default HMC IP
HMC_PORT="${HMC_PORT:-12443}"           # Default HMC REST API port
LOGIN_XML="${LOGIN_XML:-login.xml}"
OUTPUT_FILE="${OUTPUT_FILE:-pcm_data.csv}"
INTERVAL="${COLLECTION_INTERVAL:-5}"     # Data collection interval in seconds
COOKIE_FILE="cookies.txt"
AUDIT_MEMENTO="hmc_pcm_collector"

check_curl() {
    if ! whence curl >/dev/null 2>&1; then
        error "curl is not installed. Please install curl first."
        exit 1
    fi
}

# Extract value from XML tag
extract_xml_tag() {
    # Usage: extract_xml_tag <tag> <file>
    tag="$1"
    file="$2"
    sed -n "s:.*<$tag[^>]*>\\(.*\\)</$tag>.*:\\1:p" "$file"
}

# Authenticate with HMC using PUT, cookies, and extract X-API-Session
authenticate() {
    log "Authenticating with HMC at ${HMC_HOST}:${HMC_PORT}..."
    rm -f "$COOKIE_FILE" logon_response.xml
    curl -k -c "$COOKIE_FILE" -X PUT \
        -H "Content-Type: application/vnd.ibm.powervm.web+xml; type=LogonRequest" \
        -H "Accept: application/vnd.ibm.powervm.web+xml; type=LogonResponse" \
        -H "X-Audit-Memento: $AUDIT_MEMENTO" \
        -d @${LOGIN_XML} \
        "https://${HMC_HOST}:${HMC_PORT}/rest/api/web/Logon" > logon_response.xml
    
    X_API_SESSION=$(extract_xml_tag "X-API-Session" logon_response.xml)
    if [ -z "$X_API_SESSION" ]; then
        error "Authentication failed. Check credentials in ${LOGIN_XML}"
        print "Response: $(cat logon_response.xml)"
        exit 1
    fi
    log "Authentication successful. X-API-Session: ${X_API_SESSION}"
    echo "$X_API_SESSION"
}

# Get managed systems (use cookies and X-API-Session)
get_managed_systems() {
    local x_api_session="$1"
    log "Getting managed systems..."
    
    # Try without Accept header first (most compatible)
    curl -k -b "$COOKIE_FILE" -X GET \
        -H "X-API-Session: ${x_api_session}" \
        -H "X-Audit-Memento: $AUDIT_MEMENTO" \
        "https://${HMC_HOST}:${HMC_PORT}/rest/api/uom/ManagedSystem" > managed_systems.xml
    
    # Check if we got a valid response (not HTML error)
    if grep -q "Console Internal Error" managed_systems.xml; then
        log "Trying with generic Accept header..."
        curl -k -b "$COOKIE_FILE" -X GET \
            -H "X-API-Session: ${x_api_session}" \
            -H "Accept: application/vnd.ibm.powervm.web+xml" \
            -H "X-Audit-Memento: $AUDIT_MEMENTO" \
            "https://${HMC_HOST}:${HMC_PORT}/rest/api/uom/ManagedSystem" > managed_systems.xml
    fi
    
    # Check again for errors
    if grep -q "Console Internal Error" managed_systems.xml; then
        log "Trying base endpoint..."
        curl -k -b "$COOKIE_FILE" -X GET \
            -H "X-API-Session: ${x_api_session}" \
            -H "X-Audit-Memento: $AUDIT_MEMENTO" \
            "https://${HMC_HOST}:${HMC_PORT}/rest/api/uom" > managed_systems.xml
    fi
    
    # Extract system IDs using sed
    sed -n 's/.*href="[^\"]*ManagedSystem\/\([^\"]*\)".*/\1/p' managed_systems.xml
}

# Get PCM data for a system (use cookies and X-API-Session)
get_pcm_data() {
    local x_api_session="$1"
    local system_id="$2"
    log "Collecting PCM data for system: ${system_id}"
    
    # Try without Accept header first (most compatible)
    curl -k -b "$COOKIE_FILE" -X GET \
        -H "X-API-Session: ${x_api_session}" \
        -H "X-Audit-Memento: $AUDIT_MEMENTO" \
        "https://${HMC_HOST}:${HMC_PORT}/rest/api/uom/ManagedSystem/${system_id}/PerformanceAndCapacityMonitoring" > pcm_data.xml
    
    # Check if we got a valid response (not HTML error)
    if grep -q "Console Internal Error" pcm_data.xml; then
        log "Trying with generic Accept header for PCM data..."
        curl -k -b "$COOKIE_FILE" -X GET \
            -H "X-API-Session: ${x_api_session}" \
            -H "Accept: application/vnd.ibm.powervm.web+xml" \
            -H "X-Audit-Memento: $AUDIT_MEMENTO" \
            "https://${HMC_HOST}:${HMC_PORT}/rest/api/uom/ManagedSystem/${system_id}/PerformanceAndCapacityMonitoring" > pcm_data.xml
    fi
    
    cat pcm_data.xml
}

# Parse PCM data and convert to CSV
parse_pcm_to_csv() {
    local pcm_data_file="$1"
    local system_id="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    # Extract metrics
    CPU_UTIL=$(extract_xml_tag 'cpuUtilization' "$pcm_data_file"); if [ -z "$CPU_UTIL" ]; then CPU_UTIL="N/A"; fi
    MEM_UTIL=$(extract_xml_tag 'memoryUtilization' "$pcm_data_file"); if [ -z "$MEM_UTIL" ]; then MEM_UTIL="N/A"; fi
    NET_UTIL=$(extract_xml_tag 'networkUtilization' "$pcm_data_file"); if [ -z "$NET_UTIL" ]; then NET_UTIL="N/A"; fi
    STORAGE_UTIL=$(extract_xml_tag 'storageUtilization' "$pcm_data_file"); if [ -z "$STORAGE_UTIL" ]; then STORAGE_UTIL="N/A"; fi
    POWER=$(extract_xml_tag 'powerConsumption' "$pcm_data_file"); if [ -z "$POWER" ]; then POWER="N/A"; fi
    TEMP=$(extract_xml_tag 'temperature' "$pcm_data_file"); if [ -z "$TEMP" ]; then TEMP="N/A"; fi
    echo "${timestamp},${system_id},${CPU_UTIL},${MEM_UTIL},${NET_UTIL},${STORAGE_UTIL},${POWER},${TEMP}"
}

create_csv_header() {
    echo "Timestamp,System_ID,CPU_Utilization,Memory_Utilization,Network_Utilization,Storage_Utilization,Power_Consumption,Temperature" > "$OUTPUT_FILE"
    log "CSV file created: ${OUTPUT_FILE}"
}

# Logoff (use cookies and X-API-Session, use PUT)
cleanup_session() {
    local x_api_session="$1"
    if [ -n "$x_api_session" ]; then
        log "Logging out from HMC..."
        curl -k -b "$COOKIE_FILE" -X PUT \
            -H "X-API-Session: ${x_api_session}" \
            -H "Content-Type: application/vnd.ibm.powervm.web+xml; type=LogoffRequest" \
            -H "X-Audit-Memento: $AUDIT_MEMENTO" \
            "https://${HMC_HOST}:${HMC_PORT}/rest/api/web/Logoff" > /dev/null
    fi
    rm -f "$COOKIE_FILE" logon_response.xml managed_systems.xml pcm_data.xml
}

cleanup() {
    log "Script interrupted. Cleaning up..."
    cleanup_session "$X_API_SESSION"
    exit 0
}

main() {
    log "Starting IBM HMC PCM Data Collector"
    log "HMC Host: ${HMC_HOST}:${HMC_PORT}"
    log "Collection interval: ${INTERVAL} seconds"
    log "Output file: ${OUTPUT_FILE}"
    check_curl
    if [ ! -f "$LOGIN_XML" ]; then
        error "Login XML file not found: ${LOGIN_XML}"
        exit 1
    fi
    create_csv_header
    trap cleanup INT TERM
    X_API_SESSION=$(authenticate)
    SYSTEMS=$(get_managed_systems "$X_API_SESSION")
    if [ -z "$SYSTEMS" ]; then
        error "No managed systems found"
        cleanup_session "$X_API_SESSION"
        exit 1
    fi
    log "Found managed systems: $(echo "$SYSTEMS" | tr '\n' ' ')"
    while true; do
        log "Collecting PCM data..."
        for system in $SYSTEMS; do
            get_pcm_data "$X_API_SESSION" "$system" > pcm_data.xml
            CSV_LINE=$(parse_pcm_to_csv pcm_data.xml "$system")
            echo "$CSV_LINE" >> "$OUTPUT_FILE"
            log "Data collected for system: ${system}"
        done
        log "Waiting ${INTERVAL} seconds before next collection..."
        sleep "$INTERVAL"
    done
}

main "$@" 