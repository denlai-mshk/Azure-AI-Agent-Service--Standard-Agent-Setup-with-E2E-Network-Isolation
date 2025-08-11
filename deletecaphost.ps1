# Script to delete the capability host

# Prompt for required information
$subscriptionId = Read-Host "Enter Subscription ID"
$resourceGroup = Read-Host "Enter Resource Group name"
$accountName = Read-Host "Enter Foundry Account or Project name"
$caphostName = Read-Host "Enter CapabilityHost name"

function Get-AccessToken {
    # Requires Az.Accounts module
    $token = Get-AzAccessToken -AsSecureString

    # Convert SecureString token to plain text string securely
    $ssPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($token.Token)
    try {
        $plainToken = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ssPtr)
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ssPtr)
    }
    return $plainToken
}

Write-Output "Getting Azure access token..."
$accessToken = Get-AccessToken

if ([string]::IsNullOrEmpty($accessToken)) {
    Write-Error "Error: Failed to get access token. Please make sure you're logged in with 'Connect-AzAccount'"
    exit 1
}

# Debug output for input variables
Write-Output "Subscription ID: $subscriptionId"
Write-Output "Resource Group: $resourceGroup"
Write-Output "Account Name: $accountName"
Write-Output "CapabilityHost Name: '$caphostName'"

# Construct the API URL with proper variable boundary for interpolation
$apiUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$accountName/capabilityHosts/${caphostName}?api-version=2025-06-01"

Write-Output "Deleting capability host: $caphostName"
Write-Output "API URL: $apiUrl"

# Send DELETE request and capture response
Write-Output "Sending DELETE request..."
try {
    $response = Invoke-WebRequest -Uri $apiUrl -Method Delete -Headers @{ Authorization = "Bearer $accessToken" } -ContentType "application/json"
}
catch {
    Write-Error "Error: Failed to send deletion request."
    Write-Error $_.Exception.Message
    if ($_.Exception.Response) {
        $responseBody = $_.Exception.Response.Content.ReadAsStringAsync().Result
        Write-Error "Response body: $responseBody"
    }
    exit 1
}

# Check HTTP status code to determine next steps
$statusCode = $response.StatusCode.Value__

if ($statusCode -eq 202) {
    # Asynchronous operation started, look for Azure-AsyncOperation header
    $operationUrl = $response.Headers["Azure-AsyncOperation"]
    if ([string]::IsNullOrEmpty($operationUrl)) {
        Write-Error "Error: Async operation URL header not found despite 202 Accepted response."
        exit 1
    }

    Write-Output "Capability host deletion request initiated."
    Write-Output "Monitoring operation: $operationUrl"

    # Poll until operation completes
    $status = "Creating"
    while ($status -eq "Creating") {
        Write-Output "Checking operation status..."
        $accessToken = Get-AccessToken
        try {
            $operationResponse = Invoke-RestMethod -Uri $operationUrl -Headers @{ Authorization = "Bearer $accessToken"; "Content-Type" = "application/json" }
        }
        catch {
            Write-Warning "Transient error encountered. Continuing to poll..."
            Start-Sleep -Seconds 10
            continue
        }

        $errorCode = $operationResponse.error.code
        if ($errorCode -eq "TransientError") {
            Write-Output "Transient error encountered. Continuing to poll..."
            Start-Sleep -Seconds 10
            continue
        }

        $status = $operationResponse.status

        if ([string]::IsNullOrEmpty($status)) {
            Write-Error "Error: Could not determine operation status."
            Write-Output "Response: $($operationResponse | ConvertTo-Json -Depth 5)"
            exit 1
        }

        Write-Output "Current status: $status"

        if ($status -eq "Creating") {
            Write-Output "Operation still in progress. Waiting 10 seconds before checking again..."
            Start-Sleep -Seconds 10
        }
    }

    # Final status check
    if ($status -eq "Succeeded") {
        Write-Output "`nCapability host deletion completed successfully."
        exit 0
    }
    else {
        Write-Error "`nCapability host deletion failed with status: $status"
        Write-Output "Response: $($operationResponse | ConvertTo-Json -Depth 5)"
        exit 1
    }
}
elseif ($statusCode -eq 204) {
    # No Content means deletion succeeded immediately
    Write-Output "Capability host deletion completed successfully (204 No Content)."
    exit 0
}
else {
    Write-Error "Unexpected response status code: $statusCode"
    Write-Output "Response headers:"
    $response.Headers.GetEnumerator() | ForEach-Object { Write-Output "$($_.Key): $($_.Value)" }
    if ($response.Content) {
        Write-Output "Response content: $($response.Content)"
    }
    exit 1
}
