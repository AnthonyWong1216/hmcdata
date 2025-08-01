#!/bin/ksh

# Discover LPARs script
# Finds all LPARs on the specified server

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    print -u2 "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    print -u2 "${RED}[ERROR]${NC} $1"
}

# Configuration
HMC_HOST="192.168.136.104"
HMC_PORT="12443"
LOGIN_XML="login.xml"
COOKIE_FILE="cookies.txt"
AUDIT_MEMENTO="hmc_discover_lpars"
SERVER_NAME="Server-9105-22A-7892A61"

# Extract value from XML tag
extract_xml_tag() {
    tag="$1"
    file="$2"
    sed -n "s:.*<$tag[^>]*>\\(.*\\)</$tag>.*:\\1:p" "$file"
}

# Authenticate
authenticate() {
    log "Authenticating with HMC..."
    rm -f "$COOKIE_FILE" logon_response.xml
    curl -k -c "$COOKIE_FILE" -X PUT \
        -H "Content-Type: application/vnd.ibm.powervm.web+xml; type=LogonRequest" \
        -H "Accept: application/vnd.ibm.powervm.web+xml; type=LogonResponse" \
        -H "X-Audit-Memento: $AUDIT_MEMENTO" \
        -d @${LOGIN_XML} \
        "https://${HMC_HOST}:${HMC_PORT}/rest/api/web/Logon" > logon_response.xml
    
    X_API_SESSION=$(extract_xml_tag "X-API-Session" logon_response.xml)
    if [ -z "$X_API_SESSION" ]; then
        error "Authentication failed"
        exit 1
    fi
    log "Authentication successful"
    echo "$X_API_SESSION"
}

# Get LPARs
get_lpars() {
    local x_api_session="$1"
    log "Getting LPARs for server: ${SERVER_NAME}"
    
    curl -k -b "$COOKIE_FILE" -X GET \
        -H "X-API-Session: ${x_api_session}" \
        -H "X-Audit-Memento: $AUDIT_MEMENTO" \
        "https://${HMC_HOST}:${HMC_PORT}/rest/api/uom/ManagedSystem/${SERVER_NAME}/LogicalPartition" > lpars.xml
    
    # Check for errors
    if grep -q "Console Internal Error" lpars.xml; then
        log "Trying with generic Accept header..."
        curl -k -b "$COOKIE_FILE" -X GET \
            -H "X-API-Session: ${x_api_session}" \
            -H "Accept: application/vnd.ibm.powervm.web+xml" \
            -H "X-Audit-Memento: $AUDIT_MEMENTO" \
            "https://${HMC_HOST}:${HMC_PORT}/rest/api/uom/ManagedSystem/${SERVER_NAME}/LogicalPartition" > lpars.xml
    fi
    
    # Extract LPAR names
    sed -n 's/.*href="[^\"]*LogicalPartition\/\([^\"]*\)".*/\1/p' lpars.xml
}

# Cleanup
cleanup() {
    local x_api_session="$1"
    if [ -n "$x_api_session" ]; then
        log "Logging out..."
        curl -k -b "$COOKIE_FILE" -X PUT \
            -H "X-API-Session: ${x_api_session}" \
            -H "Content-Type: application/vnd.ibm.powervm.web+xml; type=LogoffRequest" \
            -H "X-Audit-Memento: $AUDIT_MEMENTO" \
            "https://${HMC_HOST}:${HMC_PORT}/rest/api/web/Logoff" > /dev/null
    fi
    rm -f "$COOKIE_FILE" logon_response.xml lpars.xml
}

# Main
main() {
    log "Starting LPAR discovery..."
    
    X_API_SESSION=$(authenticate)
    LPARS=$(get_lpars "$X_API_SESSION")
    
    if [ -z "$LPARS" ]; then
        error "No LPARs found or error occurred"
        log "Raw response:"
        cat lpars.xml
    else
        log "Found LPARs:"
        for lpar in $LPARS; do
            echo "  - $lpar"
        done
    fi
    
    cleanup "$X_API_SESSION"
}

main "$@" 