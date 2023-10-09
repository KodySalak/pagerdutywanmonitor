#Variables
$ExpectedWANIP = "<PrimaryWANIPHere>"
$PDAPIKey = "<YourPDKeyHere>"
$PDEscalationID = "<EscalationIDFromPD>"
$PDServiceID = "<ServiceIDFromPD>"
$Headers = @{"Content-Type" = "application/json"
"Authorization" = "Token token=$PDAPIKey"
"From" = "<EmailAddressAssociatedWithAPIKey>"}

Function Get-CurrentIP {
    While ($True) {
        $ResultingIP = (Invoke-WebRequest -Uri ifconfig.me -UseBasicParsing).Content
        If ($ResultingIP -ne $ExpectedWANIP -and $null -ne $ResultingIP) {
            Write-Host "IP Differs!"
            Send-PagerDutyAlert
        }
        Write-Host "WAN connection is on primary."
        Start-Sleep -Seconds 2
    }
}

Function Send-PagerDutyAlert {
    #Get date/time for unique alert ID in PagerDuty
    $CurrentTime = Get-Date -Format ddmmyyyyhhmmss
    #Build the JSON to send the alert
    $PDIncidentEndpoint = "https://api.pagerduty.com/incidents"
    $AlertIncidentData = @{
        incident = @{
            type = "incident"
            title = "WAN Failover Detected"
            description = "The Main WAN interface failed over to backup"
            urgency = "high"
            incident_key = "$CurrentTime"
            service = @{
                id = "$PDServiceID"
                type = "service_reference"
            }
            escalation_policy = @{
                id = "$PDEscalationID"
                type = "escalation_policy_reference"
            }
            body = @{
                type = "incident_body"
                details = "External testing proved a failover happened. Please check status and prepare for alert armegeddon."
            }
        }
    }
    #Convert it to JSON
    $AlertJSONBody = $AlertIncidentData | ConvertTo-Json
    #Send the alert
    $AlertResponse = Invoke-RestMethod -Uri $PDIncidentEndpoint -Method POST -Headers $Headers -Body $AlertJSONBody
    #Grab the Incident Number from the result so we can close it when failover is done
    $PDIncidentNumber = $AlertResponse.Incident.ID
    #Monitor the WAN IP forever until failback
    Write-Host "PagerDuty alert sent with ID $($PDIncidentNumber)"
    While ($ResultingIP -ne $ExpectedWANIP -and $null -ne $ResultingIP) {
        Write-Host "WAN is still failed over"
        Start-Sleep -Seconds 2
        $ResultingIP = (Invoke-WebRequest -Uri ifconfig.me -UseBasicParsing).Content
    }   
    #When it becomes the primary IP address it will exit the above While loop
    #Build JSON for resolving the alert
    Write-Host "WAN failed back, sending the resolve alert"
    $PDResolveEndpoint = "https://api.pagerduty.com/incidents/$PDIncidentNumber"
    $ResolveJSONBody = @{
        incident = @{
            type = "incident_reference"
            status = "resolved"
            body = @{
                type = "incident_body"
                details = "WAN failback detected - Resolving"
            }
        }
    }
    #Convert to JSON
    $ResolveIncidentData = $ResolveJSONBody | ConvertTo-Json
    #Send and make sure it sent
    $ResolveResponse = Invoke-RestMethod -Uri $PDResolveEndpoint -Method PUT -Headers $Headers -Body $ResolveIncidentData
    If ($ResolveResponse.incident.status -eq "resolved") {
        Write-Host "Resolve command sent successfully."
    }
    #Got back to monitor
    Get-CurrentIP
}
Get-CurrentIP
