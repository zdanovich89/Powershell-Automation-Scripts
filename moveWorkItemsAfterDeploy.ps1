function Invoke-AzureDevOpsRestMethod {
    param (
        [string]$uri,
        [string]$pat,
        [string]$method = 'Get',
        [object]$body = $null,
        [string]$contentType = 'application/json'
    )

    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)"))
    $headers = @{
        Authorization  = "Basic $base64AuthInfo"
        'Content-Type' = $contentType
    }

    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method $method -Body $body

    return $response
}

# Main script logic
$organization = ""
$project = ""
$pat = "$env:SYSTEM_ACCESSTOKEN"
$releaseDefinitionId = 131

# Get all releases for the specified definition ID
$allReleasesUri = "https://vsrm.dev.azure.com/$organization/$project/_apis/release/releases?definitionId=$releaseDefinitionId&api-version=7.1"
$allReleases = Invoke-AzureDevOpsRestMethod -uri $allReleasesUri -pat $pat
$foundSucceededStage = $false

foreach ($release in $allReleases.value) {
    $releaseUrl = "https://vsrm.dev.azure.com/$organization/$project/_apis/release/releases/$($release.id)?api-version=7.1"
    $releaseInfo = Invoke-AzureDevOpsRestMethod -uri $releaseUrl -pat $pat

    Write-Host "Release $($release.name)"

    foreach ($stage in $releaseInfo.environments) {
        Write-Host "Stage: $($stage.name), Status: $($stage.status)"
        if ($stage.name -eq 'TEST stage') {
            if ($stage.status -eq 'succeeded') {
                Write-Host "Found succeeded TEST stage. Stopping processing for this release."
                $foundSucceededStage = $true
                break
            }
            else {
                # Continue processing the release
                $foundSucceededStage = $false

                # Check different levels for artifacts
                $artifacts = $releaseInfo | Select-Object -ExpandProperty artifacts

                if ($artifacts) {
                    foreach ($artifact in $artifacts) {
                        $buildId = $artifact.definitionReference.buildUri.id -replace '\D', ''
                        Write-Host "Artifact Build ID: $buildId"

                        # Get all work items associated with the build
                        $buildWorkItemsUri = "https://dev.azure.com/$organization/$project/_apis/build/builds/$buildId/workitems?api-version=7.1"
                        $buildWorkItems = Invoke-AzureDevOpsRestMethod -uri $buildWorkItemsUri -pat $pat

                        if ($buildWorkItems.value) {
                            Write-Host "Work Items related to Build $($buildId):"
                            foreach ($workItem in $buildWorkItems.value) {
                                $workItemId = $workItem.id
                                # Get detailed information about each work item
                                $workItemDetailsUri = "https://dev.azure.com/$organization/$project/_apis/wit/workitems/$($workItemId)?api-version=7.1"
                                $workItemDetails = Invoke-AzureDevOpsRestMethod -uri $workItemDetailsUri -pat $pat

                                if ($workItemDetails) {
                                    Write-Host "Work Item ID: $($workItemDetails.id), Work Item Type: $($workItemDetails.fields.'System.WorkItemType'), Title: $($workItemDetails.fields.'System.Title'), State: $($workItemDetails.fields.'System.State')"

                                    # Check if work item is a Bug and in the New state
                                    if ($workItemDetails.fields.'System.WorkItemType' -eq 'Bug' -and $workItemDetails.fields.'System.State' -eq 'Resolved') {
                                        # Update work item to QA status
                                        $updateWorkItemUri = "https://dev.azure.com/$organization/$project/_apis/wit/workitems/$($workItemId)?api-version=7.1"                            
                                        $body = @"
                                        [
                                            {
                                            "op": "add",
                                            "path": "/fields/System.State",
                                            "value": "QA"
                                            }
                                        ]
"@
                                        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)"))
                                        $headers = @{
                                            Authorization  = "Basic $base64AuthInfo"
                                            'Content-Type' = 'application/json-patch+json'
                                        }
                                        $response = Invoke-RestMethod -Uri $updateWorkItemUri -Headers $headers -Method Patch -Body $body                           
                                        Write-Host "Work Item updated to QA."
                                    }
                                }
                                else {
                                    Write-Host "Failed to retrieve details for Work Item ID: $workItemId"
                                }
                            }
                        }
                        else {
                            Write-Host "No work items found for Build $buildId."
                        }
                    }
                }
                else {
                    Write-Host "No artifacts found."
                }

                Write-Host "------------------------"
            }
        }
    }

    if ($foundSucceededStage) {
        break
    }
}
