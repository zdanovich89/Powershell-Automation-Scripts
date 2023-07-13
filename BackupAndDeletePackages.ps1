$connectionToken = "${env:SYSTEM_ACCESSTOKEN}"
$organization = "NsureInc"
$project = "Nsure"
$backupDirectory = "${env:BUILD_ARTIFACTSTAGINGDIRECTORY}/Backup"
$feedId = "54020765-35d1-4554-9333-bcb8a7a9fa6a"
$failedRequests = @()
$deletedPackages = @()
$backedUpPackages = @()

# Create the backup directory if it doesn't exist
if (!(Test-Path $backupDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $backupDirectory | Out-Null
}

$packagesUrl = "https://feeds.dev.azure.com/$organization/$project/_apis/packaging/Feeds/$feedId/packages?api-version=6.0-preview.1"

$packagesInFeed = Invoke-RestMethod -Uri $packagesUrl -Method Get -Headers @{Authorization=("Bearer {0}" -f $connectionToken)}
$packagesId = $packagesInFeed.value.id

ForEach ($packageId in $packagesId) {
    $packageVersionUrl = "https://feeds.dev.azure.com/$organization/$project/_apis/packaging/Feeds/$feedId/packages/$($packageId)/versions?api-version=6.0-preview.1"
    $packageVersions = Invoke-RestMethod -Uri $packageVersionUrl -Method Get -Headers @{Authorization=("Bearer {0}" -f $connectionToken)}
    $versions = $packageVersions.value | ForEach-Object { $_.version }

    $packageNameUrl = "https://feeds.dev.azure.com/$organization/$project/_apis/packaging/Feeds/$feedId/packages/$($packageId)?api-version=6.0-preview.1"
    $packageName = (Invoke-RestMethod -Uri $packageNameUrl -Method Get -Headers @{Authorization=("Bearer {0}" -f $connectionToken)}).name

    foreach ($version in $versions) {
        $backupFileName = "$packageName-$version.nupkg"
        $backupFilePath = Join-Path -Path $backupDirectory -ChildPath $backupFileName

        Write-Host "Backing up Package: $packageName - Version: $version"

        $downloadUrl = "https://pkgs.dev.azure.com/$organization/$project/_apis/packaging/feeds/$feedId/nuget/packages/$packageName/versions/$version/content?api-version=6.1-preview.1"

        $attempt = 1
        $maxAttempts = 2
        $success = $false

        while ($attempt -le $maxAttempts) {
            try {
                Invoke-RestMethod -Uri $downloadUrl -Method Get -Headers @{Authorization=("Bearer {0}" -f $connectionToken)} -OutFile $backupFilePath
                $success = $true
                break  # Break the loop if the request succeeds
            } catch {
                Write-Host "Failed to download package (Attempt $attempt): Package ID: $packageId, Package Name: $packageName, Version: $version"
                $attempt++                
            }
        }

        if ($success) {
            $backedUpPackages += @{
                PackageName = $packageName
                Version = $version                
            }
        } else {
            $failedRequests += @{
                PackageName = $packageName               
                Version = $version                
            }
        }
    }
}

ForEach ($packageId in $packagesId) {
    $packageVersionUrl = "https://feeds.dev.azure.com/$organization/$project/_apis/packaging/Feeds/$feedId/packages/$($packageId)/versions?api-version=6.0-preview.1"
    
    try {
        $packageVersions = Invoke-RestMethod -Uri $packageVersionUrl -Method Get -Headers @{Authorization=("Bearer {0}" -f $connectionToken)}
    } catch {
        Write-Host "Failed to retrieve package versions for Package ID: $packageId"
        Write-Host "Skipping to the next package..."
        continue
    }

    $sortedPackageVersions = $packageVersions.value | Sort-Object { [DateTime]$_."publishDate" } -Descending

    $versions = $sortedPackageVersions | ForEach-Object { $_.version } 
    $publishDates = $sortedPackageVersions | ForEach-Object { $_.publishDate } 

    $packageNameUrl = "https://feeds.dev.azure.com/$organization/$project/_apis/packaging/Feeds/$feedId/packages/$($packageId)?api-version=6.0-preview.1"
    $packageName = (Invoke-RestMethod -Uri $packageNameUrl -Method Get -Headers @{Authorization=("Bearer {0}" -f $connectionToken)}).name   

    $firstAlphaFound = $false

    foreach ($versionIndex in 0..($versions.Length - 1)) {
        $version = $versions[$versionIndex]
        $publishDate = $publishDates[$versionIndex]

        if ($version -like "*alpha*") {
            $publishDateTime = [DateTime]::Parse($publishDate)
            $daysDifference = (Get-Date) - $publishDateTime

            if ($daysDifference.Days -gt 30) {
                if (!$firstAlphaFound) {
                    $firstAlphaFound = $true
                    continue  # Skip the first 'alpha' version
                }

                # Check if the version is present in failedRequests
                $versionInFailedRequests = $failedRequests | Where-Object { $_.PackageId -eq $packageId -and $_.Version -eq $version }

                if ($versionInFailedRequests) {
                    Write-Host "Skipping deletion of Package ID: $packageId, Version: $version as it is present in failed requests"
                } else {
                    Write-Host "The next package version will be DELETE:"                    
                    Write-Host "Package Name: $packageName"
                    Write-Host "Version: $version (Older than 30 days)"
                    Write-Host "Publish Date: $publishDateTime"
                    Write-Host "----------------------------------"
                
                    $deleteUrl = "https://pkgs.dev.azure.com/$organization/$project/_apis/packaging/feeds/$feedId/nuget/packages/$($packageName)/versions/$($version)?api-version=5.1-preview.1"
                
                    # Invoke-RestMethod -Uri $deleteUrl -Method Delete -Headers @{Authorization=("Bearer {0}" -f $connectionToken)}
                    # Write-Host "Package version deleted: $version"
                    # Write-Host "----------------------------------"

                    $deletedPackages += @{                                       
                        PackageName = $packageName
                        Version = $version
                    }
                }
            }
        }  
    }  
}

# Show all backup files
Write-Host "BACKUP FILES: "
foreach ($backupFile in $backedUpPackages) {
    $packageName = $backupFile.PackageName
    $version = $backupFile.Version
    Write-Host "Package: $packageName, Version: $version"
}

Write-Host "=============================================================================== `n"

# Show all failed requests
Write-Host "FAILED REQUESTS: "
foreach ($failedRequest in $failedRequests) {
    $packageName = $failedRequest.PackageName
    $version = $failedRequest.Version
    Write-Host "Package: $packageName, Version: $version"
}

Write-Host "=============================================================================== `n"

# Show all deleted packages
Write-Host "DELETED PAKCAGES: "
foreach ($deletedPackage in $deletedPackages) {
    $packageName = $deletedPackage.PackageName
    $version = $deletedPackage.Version
    Write-Host "Package: $packageName, Version: $version"
}

