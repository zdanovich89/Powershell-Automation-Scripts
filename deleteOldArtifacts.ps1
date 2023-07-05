$connectionToken = ${env:SYSTEM_ACCESSTOKEN}
$base64AuthHeader = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$connectionToken"))
$organization = "NsureInc"
$feedId = "19591a36-9ce9-4135-99b0-d1ade9290f0a"

$packagesUrl = "https://feeds.dev.azure.com/$organization/_apis/packaging/Feeds/$feedId/packages?api-version=6.0-preview.1"

$packagesInFeed = Invoke-RestMethod -Uri $packagesUrl -Method Get -Headers @{Authorization=("Basic {0}" -f $base64AuthHeader)}
$sortedPackages = $packagesInFeed.value | Sort-Object { [DateTime]$_.versions[0].publishDate } -Descending

$packagesId = $sortedPackages | ForEach-Object { $_.id }

ForEach ($packageId in $packagesId)
{
    $packageVersionUrl = "https://feeds.dev.azure.com/$organization/_apis/packaging/Feeds/$feedId/packages/$($packageId)/versions?api-version=6.0-preview.1"
    $packageVersions = Invoke-RestMethod -Uri $packageVersionUrl -Method Get -Headers @{Authorization=("Basic {0}" -f $base64AuthHeader)}

    $versions = $packageVersions.value.version
    $publishDates = $packageVersions.value.publishDate

    $packageNameUrl = "https://feeds.dev.azure.com/$organization/_apis/packaging/Feeds/$feedId/packages/$($packageId)?api-version=6.0-preview.1"
    $packageName = (Invoke-RestMethod -Uri $packageNameUrl -Method Get -Headers @{Authorization=("Basic {0}" -f $base64AuthHeader)}).name   

    foreach ($versionIndex in 1..($versions.Length - 1)) {
        $version = $versions[$versionIndex]
        $publishDate = $publishDates[$versionIndex]

        if ($version -like "*alpha*") {
            $publishDateTime = [DateTime]::Parse($publishDate)
            $daysDifference = (Get-Date) - $publishDateTime

            if ($daysDifference.Days -gt 30) {
                Write-Host "The next package version will be DELETE:"
                Write-Host "Package Name: $packageName"
                Write-Host "Version: $version (Older than 30 days)"
                Write-Host "Publish Date: $publishDate"
                Write-Host "----------------------------------"

                # $deleteUrl = "https://feeds.dev.azure.com/$organization/_apis/packaging/Feeds/$feedId/packages/$($packageId)/versions/$version?api-version=6.0-preview.1"
                # Invoke-RestMethod -Uri $deleteUrl -Method Delete -Headers @{Authorization=("Basic {0}" -f $base64AuthHeader)}
                # Write-Host "Package version deleted: $version"
                # Write-Host "----------------------------------"
            }
        }  
    }  
}

