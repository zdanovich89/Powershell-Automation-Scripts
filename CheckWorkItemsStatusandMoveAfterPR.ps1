$organization = "home-org"
$project = "work"
$repositoryId = "work"
$pullRequestId = "23"
$pat = ${env:SYSTEM_ACCESSTOKEN}
$requestBody = '[
    {
        "op" : "add",
        "path": "/fields/System.State",
        "value": "Closed"
    } 
]'

# Define the API endpoints
$baseUrl = "https://dev.azure.com/$organization/$project"
$pullRequestUrl = "$baseUrl/_apis/git/repositories/$repositoryId/pullRequests/$pullRequestId"
$workItemsUrl = "$baseUrl/_apis/wit/workitems"

# Create the Authorization header with Personal Access Token
$base64AuthHeader = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))

try {
    # Get the link to work items
    $pullRequest = Invoke-RestMethod -Uri $pullRequestUrl -Headers @{Authorization = "Basic $base64AuthHeader"}
    $linkWorkItems = $pullRequest._links.workItems.href

    # Get all work item IDs
    $workItemsResponse = Invoke-RestMethod -Uri $linkWorkItems -Headers @{Authorization = "Basic $base64AuthHeader"}
    $workItems = $workItemsResponse.value

    foreach ($workItem in $workItems) {
        # Get info about each work item
        $workItemId = $workItem.id
        $uriBuilder = New-Object System.UriBuilder("$workItemsUrl/$workItemId")
        $uriBuilder.Query = '$expand=relations'
        $workItemUrlWithRelations = $uriBuilder.ToString()
        $workItemData = Invoke-RestMethod -Uri $workItemUrlWithRelations -Headers @{Authorization = "Basic $base64AuthHeader"}
        $hasChildItems = $workItemData.relations | Where-Object { $_.rel -eq 'System.LinkTypes.Hierarchy-Forward' }

        if (($workItemData.fields.'System.WorkItemType' -eq "Bug" -and $workItemData.fields."System.State" -eq "Resolved") -or
            ($workItemData.fields.'System.WorkItemType' -eq "User Story" -and $workItemData.fields."System.State" -eq "New")) {

            # Send the PATCH request to update the work item state
            $workItemPatchUrl = "$($workItemsUrl)/$($workItemId)?api-version=7.0"
            Invoke-RestMethod -Uri $workItemPatchUrl -Method Patch -Headers @{
                Authorization = "Basic $base64AuthHeader"
                "Content-Type" = "application/json-patch+json"
            } -Body $requestBody

            $updatedWorkItemData = Invoke-RestMethod -Uri $workItemUrlWithRelations -Headers @{Authorization = "Basic $base64AuthHeader"}
            Write-Host "=======///////  Updated work item $($updatedWorkItemData.id) state to: $($updatedWorkItemData.fields.'System.State') ////==========="
        } else {
            Write-Host "Work item $($workItem.id) does not match the move conditions"
        }

        if ($hasChildItems) {
            foreach ($childItemRelation in $hasChildItems) {
                $childItemId = $childItemRelation.url.Split("/")[-1]
                Write-Host "Child Work Item ID: $childItemId"
                $childWorkItem = Invoke-RestMethod -Uri "$workItemsUrl/$childItemId" -Headers @{Authorization = "Basic $base64AuthHeader"}

                if (($childWorkItem.fields.'System.WorkItemType' -eq "Bug" -and $childWorkItem.fields."System.State" -eq "Resolved") -or
                    ($childWorkItem.fields.'System.WorkItemType' -eq "User Story" -and $childWorkItem.fields."System.State" -eq "New")) {

                    # Send the PATCH request to update the child work item's column
                    $workChildItemPatchUrl = "$($workItemsUrl)/$($childItemId)?api-version=7.0"
                    Invoke-RestMethod -Uri $workChildItemPatchUrl -Method Patch -Headers @{
                        Authorization = "Basic $base64AuthHeader"
                        "Content-Type" = "application/json-patch+json"
                    } -Body $requestBody

                    $updatedChildWorkItem = Invoke-RestMethod -Uri "$workItemsUrl/$childItemId" -Headers @{Authorization = "Basic $base64AuthHeader"}

                    Write-Host "Updated child work item $($updatedChildWorkItem.id) state to: $($updatedChildWorkItem.fields.'System.State')"
                } else {
                    Write-Host "Child work item $($childItemId) does not match the move conditions"
                }
            }
        }
    }

    Write-Host "Work items have been updated successfully."
} catch {
    Write-Host "An error occurred while updating work items."
    Write-Host $_.Exception.Message
}

