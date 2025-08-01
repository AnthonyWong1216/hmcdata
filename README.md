# IBM HMC PCM Data Collector

This script collects Performance and Capacity Monitoring (PCM) data from IBM HMC consoles using REST API and outputs the data in CSV format.

## Features

- **REST API Integration**: Uses IBM HMC REST API for data collection
- **CSV Output**: Exports data in comma-separated values format
- **Multi-System Support**: Collects data from all managed systems
- **Session Management**: Handles authentication and session cleanup
- **Error Handling**: Robust error handling with retry mechanisms
- **Configurable**: Easy configuration through config file
- **Logging**: Comprehensive logging with different levels

## Prerequisites

- **curl**: Must be installed on the system
- **bash**: Script requires bash shell
- **Network Access**: Must be able to reach the HMC console
- **Valid Credentials**: HMC login credentials in login.xml

## Files

- `hmc_pcm_collector.sh`: Main collection script
- `hmc_config.sh`: Configuration file
- `login.xml`: HMC authentication credentials
- `pcm_data.csv`: Output CSV file (created by script)

## Setup

### 1. Configure HMC Connection

Edit `hmc_config.sh` and update the HMC connection settings:

```bash
export HMC_HOST="192.168.1.100"    # Your HMC IP address
export HMC_PORT="12443"             # HMC REST API port
```

### 2. Update Login Credentials

Ensure `login.xml` contains valid HMC credentials:

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<LogonRequest xmlns="http://www.ibm.com/xmlns/systems/power/firmware/web/mc/2012_10/" schemaVersion="V1_0">
  <UserID>hscroot</UserID>
  <Password>your_password</Password>
</LogonRequest>
```

### 3. Make Script Executable

```bash
chmod +x hmc_pcm_collector.sh
chmod +x hmc_config.sh
```

## Usage

### Basic Usage

```bash
# Source configuration and run script
source hmc_config.sh
./hmc_pcm_collector.sh
```

### Advanced Usage

```bash
# Run with custom configuration
HMC_HOST="10.1.1.100" COLLECTION_INTERVAL=10 ./hmc_pcm_collector.sh
```

### Background Execution

```bash
# Run in background
nohup ./hmc_pcm_collector.sh > hmc_collector.log 2>&1 &

# Check status
ps aux | grep hmc_pcm_collector
```

## Configuration Options

### Data Collection Settings

- `COLLECTION_INTERVAL`: Time between data collections (seconds)
- `OUTPUT_FILE`: CSV output filename
- `LOGIN_XML`: Authentication XML file

### PCM Data Collection

- `COLLECT_CPU`: Enable/disable CPU utilization collection
- `COLLECT_MEMORY`: Enable/disable memory utilization collection
- `COLLECT_NETWORK`: Enable/disable network utilization collection
- `COLLECT_STORAGE`: Enable/disable storage utilization collection
- `COLLECT_POWER`: Enable/disable power consumption collection
- `COLLECT_TEMPERATURE`: Enable/disable temperature collection

### Error Handling

- `CONTINUE_ON_ERROR`: Continue collection if some systems fail
- `EXIT_ON_AUTH_FAILURE`: Exit script if authentication fails
- `MAX_RETRIES`: Maximum retry attempts for failed requests

## Output Format

The script generates a CSV file with the following columns:

```
Timestamp,System_ID,CPU_Utilization,Memory_Utilization,Network_Utilization,Storage_Utilization,Power_Consumption,Temperature
```

Example output:
```
2024-01-15 10:30:15,server1,85.2,67.8,45.1,23.4,1200,45
2024-01-15 10:30:20,server2,92.1,78.3,52.7,31.2,1350,48
```

## Monitoring and Logging

### Log Levels

- **INFO**: General information and status updates
- **WARN**: Warning messages for non-critical issues
- **ERROR**: Error messages for critical failures

### Log Output

The script provides colored output:
- 🟢 Green: Information messages
- 🟡 Yellow: Warning messages
- 🔴 Red: Error messages

## Troubleshooting

### Common Issues

1. **Connection Failed**
   - Check HMC IP address and port
   - Verify network connectivity
   - Ensure firewall allows HTTPS traffic

2. **Authentication Failed**
   - Verify credentials in login.xml
   - Check HMC user permissions
   - Ensure REST API is enabled on HMC

3. **No Managed Systems Found**
   - Check HMC configuration
   - Verify managed systems are properly configured
   - Check user permissions for system access

4. **Data Collection Errors**
   - Check system status on HMC
   - Verify PCM is enabled on managed systems
   - Check network connectivity to managed systems

### Debug Mode

Enable debug logging by setting:

```bash
export LOG_LEVEL="DEBUG"
```

### Manual Testing

Test individual components:

```bash
# Test authentication
curl -k -X POST -H "Content-Type: application/vnd.ibm.powervm.web+xml; type=LogonRequest" -d @login.xml https://HMC_IP:12443/rest/api/web/Logon

# Test system list
curl -k -X GET -H "X-API-Session: SESSION_ID" -H "Accept: application/vnd.ibm.powervm.web+xml; type=ManagedSystemList" https://HMC_IP:12443/rest/api/uom/ManagedSystem
```

## Security Considerations

- **Credentials**: Store login.xml securely with appropriate permissions
- **Network**: Use VPN or secure network for HMC access
- **Firewall**: Configure firewall to allow HTTPS traffic to HMC
- **Logs**: Secure log files containing sensitive information

## Performance Considerations

- **Collection Interval**: Balance between data granularity and system load
- **Concurrent Requests**: Script handles multiple systems sequentially
- **Session Management**: Automatic session cleanup prevents resource leaks
- **Error Handling**: Retry mechanisms prevent data loss

## Integration

### Data Analysis

The CSV output can be imported into:
- **Excel**: For basic analysis and charts
- **Python**: Using pandas for advanced analysis
- **R**: For statistical analysis
- **Grafana**: For real-time monitoring dashboards

### Automation

Integrate with monitoring systems:
- **Nagios**: For alerting on threshold violations
- **Zabbix**: For centralized monitoring
- **Prometheus**: For metrics collection

## Support

For issues and questions:
1. Check the troubleshooting section
2. Enable debug logging
3. Review HMC documentation
4. Check IBM support resources

## Version History

- **v1.0**: Initial release with basic PCM data collection
- **v1.1**: Added configuration file and improved error handling
- **v1.2**: Enhanced logging and CSV output formatting 