# Use the system access token provided by Azure DevOps
$pat = $env:SYSTEM_ACCESSTOKEN
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes((":$($pat)")))
$headers = @{
    Authorization=("Basic {0}" -f $base64AuthInfo)
}

# Check if the required variables are provided
if (-not $env:organization -or -not $env:project -or -not $env:build_id) {
    Write-Host "Organization, project, or build ID is not provided. Exiting script."
    exit
}

# Construct the URLs
$leasesUrl = "https://dev.azure.com/$env:organization/$env:project/_apis/build/retention/leases?definitionId=$env:build_id&api-version=7.1-preview.1"

try {
    # Get retention leases
    $leases = Invoke-RestMethod -Uri $leasesUrl -Method Get -Headers $headers
} catch {
    Write-Host "Error getting retention leases. $_"
    exit 1
}

# Check if the response includes the necessary information
if (-not $leases -or -not $leases.value) {
    Write-Host "No retention leases found for build $($env:build_id). Exiting script."
    exit
}

# Delete retention leases
foreach ($lease in $leases.value) {
    $leaseId = $lease.leaseId    
    $deleteUrl = "https://dev.azure.com/$env:organization/$env:project/_apis/build/retention/leases?ids=$leaseId&api-version=7.1-preview.2"
    
    try {
        Invoke-RestMethod -Uri $deleteUrl -Method Delete -Headers $headers -ContentType "application/json"
        Write-Host "Retention lease $leaseId for build $($env:build_id) deleted successfully."
    } catch {
        Write-Host "Error deleting retention lease $leaseId. $_"       
    }
}

Write-Host "Script completed."
