#!/bin/bash

# IBM HMC Configuration File
# Source this file to set configuration variables

# HMC Connection Settings
export HMC_HOST="192.168.1.100"    # Change to your HMC IP address
export HMC_PORT="12443"             # Default HMC REST API port (HTTPS)
export HMC_USERNAME="hscroot"       # HMC username
export HMC_PASSWORD="abcd1234"      # HMC password (from login.xml)

# Data Collection Settings
export COLLECTION_INTERVAL=5        # Data collection interval in seconds
export OUTPUT_FILE="pcm_data.csv"   # Output CSV file name
export LOGIN_XML="login.xml"        # Login XML file name

# Logging Settings
export LOG_LEVEL="INFO"             # DEBUG, INFO, WARN, ERROR
export LOG_FILE=""                  # Leave empty for console output only

# Advanced Settings
export CURL_TIMEOUT=30              # curl timeout in seconds
export MAX_RETRIES=3                # Maximum retry attempts for failed requests
export SESSION_TIMEOUT=3600         # Session timeout in seconds (1 hour)

# PCM Data Collection Settings
export COLLECT_CPU=true             # Collect CPU utilization
export COLLECT_MEMORY=true          # Collect memory utilization
export COLLECT_NETWORK=true         # Collect network utilization
export COLLECT_STORAGE=true         # Collect storage utilization
export COLLECT_POWER=true           # Collect power consumption
export COLLECT_TEMPERATURE=true     # Collect temperature data

# CSV Output Settings
export CSV_DELIMITER=","            # CSV field delimiter
export CSV_INCLUDE_HEADER=true      # Include header in CSV file
export CSV_TIMESTAMP_FORMAT="%Y-%m-%d %H:%M:%S"  # Timestamp format

# Error Handling
export CONTINUE_ON_ERROR=true       # Continue collection even if some systems fail
export EXIT_ON_AUTH_FAILURE=true   # Exit if authentication fails 