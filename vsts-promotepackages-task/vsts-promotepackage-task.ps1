[CmdletBinding()]
param()

$feedName = Get-VstsInput -Name feed
$packageId = Get-VstsInput -Name definition
$packageVersion = Get-VstsInput -Name version
$releaseView = Get-VstsInput -Name releaseView
$pattern = Get-VstsInput -name pattern

if ($env:SYSTEM_TEAMFOUNDATIONSERVERURI -like '*visualstudio*') {
    Write-Verbose "VSTS MODE"
    $account = ($env:SYSTEM_TEAMFOUNDATIONSERVERURI -replace "https://(.*)\.visualstudio\.com/", '$1').split('.')[0]
    $basepackageurl = ("https://{0}.pkgs.visualstudio.com/DefaultCollection/_apis/packaging/feeds" -f $account)
    $basefeedsurl = ("https://{0}.feeds.visualstudio.com/DefaultCollection/_apis/packaging/feeds" -f $account)
}
else {
    write-Verbose "ONPREM MODE"
    $basepackageurl = $env:SYSTEM_TEAMFOUNDATIONSERVERURI + "_apis/packaging/feeds";
    $basefeedsurl = $env:SYSTEM_TEAMFOUNDATIONSERVERURI + "_apis/packaging/feeds";
}
function InitializeRestHeaders() {
    $restHeaders = New-Object -TypeName "System.Collections.Generic.Dictionary[[String], [String]]"
    if ([string]::IsNullOrWhiteSpace($connectedServiceName)) {
        $patToken = GetAccessToken $connectedServiceDetails
        ValidatePatToken $patToken
        $restHeaders.Add("Authorization", [String]::Concat("Bearer ", $patToken))
		
    }
    else {
        $Username = $connectedServiceDetails.Authorization.Parameters.Username
        Write-Verbose "Username = $Username" -Verbose
        $Password = $connectedServiceDetails.Authorization.Parameters.Password
        $alternateCreds = [String]::Concat($Username, ":", $Password)
        $basicAuth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($alternateCreds))
        $restHeaders.Add("Authorization", [String]::Concat("Basic ", $basicAuth))
    }
    return $restHeaders
}

function GetAccessToken($vssEndPoint) {
    $endpoint = (Get-VstsEndpoint -Name SystemVssConnection -Require)
    $vssCredential = [string]$endpoint.auth.parameters.AccessToken	
    return $vssCredential
}

function ValidatePatToken($token) {
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Unable to generate Personal Access Token for the user. Contact Project Collection Administrator"
    }
}

function Set-PackageQuality {
    
    if ($packageId) {
        write-verbose "Single package mode";
        # First get the name of the package (strange REST API behavior) and the Package Feed Type
        $packageURL = "$basefeedsurl/$feedName/packages/$packageId/?api-version=2.0-preview"
        $packResponse = Invoke-RestMethod -Uri $packageURL -Headers $headers -ContentType "application/json" -Method Get 

        $feedType = $packResponse.protocolType
        $packageName = $packResponse.normalizedName


        #API URL is slightly different for npm vs. nuget...
        switch ($feedType) {
            "npm" { $releaseViewURL = "$basepackageurl/$feedName/$feedType/$packageName/versions/$($packageVersion)?api-version=3.1-preview" }
            "nuget" { $releaseViewURL = "$basepackageurl/$feedName/$feedType/packages/$packageName/versions/$($packageVersion)?api-version=3.1-preview" }
            default { $releaseViewURL = "$basepackageurl/$feedName/$feedType/packages/$packageName/versions/$($packageVersion)?api-version=3.1-preview" }
        }
        $viewUrl="$basefeedUrl/$feedName/views/releaseView?api-version=3.0-preview"
        $response = Invoke-RestMethod -Uri $viewUrl -Headers $headers -ContentType "application/json" -Method Get 
        $releaseView = $response.id;
        $json = @{
            views = @{
                op    = "add"
                path  = "/views/-"
                value = "$releaseView"
            }
        }
        Write-Host $releaseViewURL
        $response = Invoke-RestMethod -Uri $releaseViewURL -Headers $headers   -ContentType "application/json" -Method Patch -Body (ConvertTo-Json $json)
        return $response
    }
    else {
        Write-Verbose "Multiple package mode $pattern";
        $files = get-childitem -path $pattern;
        $files | ForEach-Object {
            $filename = $_.Name;
            if ($filename -like '*.symbols.nupkg'){
                $feedName2 = "$feedName-symbols";
            }
            else {$feedName2=$feedName;}
            $viewUrl="$basefeedsUrl/$feedName2/views/$($releaseView)?api-version=3.1-preview"
            Write-Verbose $viewUrl;
            $response = Invoke-RestMethod -Uri $viewUrl -Headers $headers -ContentType "application/json" -Method Get 
            $releaseView2 = $response.id;
            $filename -match '(?<pkgname>.*)\.(?<versionid>[\.2]\.[\d]{4}\.[\d]{3,4}\.[\d]{2})';
            $pkgname = $matches.pkgname;
            $versionid = $matches.versionid;
            $packageVersion = $versionid;
            Write-Host "Promoting $($pkgname) at version $($versionid) to $($releaseView)";
            $packageURL="$basefeedsurl/$feedName2/packages/?api-version=3.0-preview&includeUrls=false&packageNameQuery=$pkgName"
            $packResponse = (Invoke-RestMethod -Uri $packageURL -Headers $headers -ContentType "application/json" -Method Get).value[0]; 
            $feedType = $packResponse.protocolType
            $packageName = $packResponse.normalizedName
             #API URL is slightly different for npm vs. nuget...
            switch ($feedType) {
                "npm" { $releaseViewURL = "$basepackageurl/$feedName2/$feedType/$packageName/versions/$($packageVersion)?api-version=3.1-preview" }
                "nuget" { $releaseViewURL = "$basepackageurl/$feedName2/$feedType/packages/$packageName/versions/$($packageVersion)?api-version=3.1-preview" }
                default { $releaseViewURL = "$basepackageurl/$feedName2/$feedType/packages/$packageName/versions/$($packageVersion)?api-version=3.1-preview" }
            }
        
            $json = @{
                views = @{
                    op    = "add"
                    path  = "/views/-"
                    value = "$releaseView2"
                }
            }
            Write-Verbose $releaseViewURL
            $response = Invoke-RestMethod -Uri $releaseViewURL -Headers $headers  -ContentType "application/json" -Method Patch -Body (ConvertTo-Json $json)
            return $response
         }
    }
    # # First get the name of the package (strange REST API behavior) and the Package Feed Type
    # $packageURL = "$basefeedsurl/$feedName/packages/$packageId/?api-version=2.0-preview"
    # $packResponse = Invoke-RestMethod -Uri $packageURL -Headers $headers -ContentType "application/json" -Method Get 

    # $feedType = $packResponse.protocolType
    # $packageName = $packResponse.normalizedName


    # #API URL is slightly different for npm vs. nuget...
    # switch ($feedType) {
    #     "npm" { $releaseViewURL = "$basepackageurl/$feedName/$feedType/$packageName/versions/$($packageVersion)?api-version=3.1-preview" }
    #     "nuget" { $releaseViewURL = "$basepackageurl/$feedName/$feedType/packages/$packageName/versions/$($packageVersion)?api-version=3.1-preview" }
    #     default { $releaseViewURL = "$basepackageurl/$feedName/$feedType/packages/$packageName/versions/$($packageVersion)?api-version=3.1-preview" }
    # }
    
    # $json = @{
    #     views = @{
    #         op    = "add"
    #         path  = "/views/-"
    #         value = "$releaseView"
    #     }
    # }
    # Write-Host $releaseViewURL
    # $response = Invoke-RestMethod -Uri $releaseViewURL -Headers $headers   -ContentType "application/json" -Method Patch -Body (ConvertTo-Json $json)
    # return $response
}

$headers = InitializeRestHeaders
Set-PackageQuality