#!/bin/ksh

# IBM HMC LPAR CPU Data Collector (ksh, HMC REST API v2)
# Collects LPAR CPU data every 5 seconds using REST API and outputs in CSV format

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
OUTPUT_FILE="${OUTPUT_FILE:-lpar_cpu_data.csv}"
INTERVAL="${COLLECTION_INTERVAL:-5}"     # Data collection interval in seconds
COOKIE_FILE="cookies.txt"
AUDIT_MEMENTO="hmc_lpar_cpu_collector"

# Hard-coded server and LPAR
SERVER_NAME="Server-9105-22A-7892A61"
LPAR_NAME="lpar1"  # Change this to your LPAR name if different

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

# Get LPAR CPU data for the specific server and LPAR
get_lpar_cpu_data() {
    local x_api_session="$1"
    log "Collecting LPAR CPU data for server: ${SERVER_NAME}, LPAR: ${LPAR_NAME}"
    
    # Try to get LPAR CPU data
    curl -k -b "$COOKIE_FILE" -X GET \
        -H "X-API-Session: ${x_api_session}" \
        -H "X-Audit-Memento: $AUDIT_MEMENTO" \
        "https://${HMC_HOST}:${HMC_PORT}/rest/api/uom/ManagedSystem/${SERVER_NAME}/LogicalPartition/${LPAR_NAME}/ProcessorRuntime" > lpar_cpu_data.xml
    
    # Check if we got a valid response (not HTML error)
    if grep -q "Console Internal Error" lpar_cpu_data.xml; then
        log "Trying with generic Accept header for LPAR CPU data..."
        curl -k -b "$COOKIE_FILE" -X GET \
            -H "X-API-Session: ${x_api_session}" \
            -H "Accept: application/vnd.ibm.powervm.web+xml" \
            -H "X-Audit-Memento: $AUDIT_MEMENTO" \
            "https://${HMC_HOST}:${HMC_PORT}/rest/api/uom/ManagedSystem/${SERVER_NAME}/LogicalPartition/${LPAR_NAME}/ProcessorRuntime" > lpar_cpu_data.xml
    fi
    
    cat lpar_cpu_data.xml
}

# Parse LPAR CPU data and convert to CSV
parse_lpar_cpu_to_csv() {
    local cpu_data_file="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Extract CPU metrics
    CPU_UTIL=$(extract_xml_tag 'cpuUtilization' "$cpu_data_file"); if [ -z "$CPU_UTIL" ]; then CPU_UTIL="N/A"; fi
    ENTITLED_CPU=$(extract_xml_tag 'entitledProcUnits' "$cpu_data_file"); if [ -z "$ENTITLED_CPU" ]; then ENTITLED_CPU="N/A"; fi
    CONFIGURED_CPU=$(extract_xml_tag 'configuredProcUnits' "$cpu_data_file"); if [ -z "$CONFIGURED_CPU" ]; then CONFIGURED_CPU="N/A"; fi
    
    echo "${timestamp},${SERVER_NAME},${LPAR_NAME},${CPU_UTIL},${ENTITLED_CPU},${CONFIGURED_CPU}"
}

create_csv_header() {
    echo "Timestamp,Server_Name,LPAR_Name,CPU_Utilization,Entitled_CPU,Configured_CPU" > "$OUTPUT_FILE"
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
    rm -f "$COOKIE_FILE" logon_response.xml lpar_cpu_data.xml
}

cleanup() {
    log "Script interrupted. Cleaning up..."
    cleanup_session "$X_API_SESSION"
    exit 0
}

main() {
    log "Starting IBM HMC LPAR CPU Data Collector"
    log "HMC Host: ${HMC_HOST}:${HMC_PORT}"
    log "Server: ${SERVER_NAME}"
    log "LPAR: ${LPAR_NAME}"
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
    
    log "Starting data collection for ${SERVER_NAME}/${LPAR_NAME}..."
    
    while true; do
        log "Collecting LPAR CPU data..."
        
        get_lpar_cpu_data "$X_API_SESSION" > lpar_cpu_data.xml
        CSV_LINE=$(parse_lpar_cpu_to_csv lpar_cpu_data.xml)
        echo "$CSV_LINE" >> "$OUTPUT_FILE"
        log "Data collected for ${SERVER_NAME}/${LPAR_NAME}"
        
        log "Waiting ${INTERVAL} seconds before next collection..."
        sleep "$INTERVAL"
    done
}

main "$@" 