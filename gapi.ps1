#https://monteledwards.com/2017/03/05/powershell-oauth-downloadinguploading-to-google-drive-via-drive-api/
#https://gist.github.com/LindaLawton/55115de5e8b366be3969b24884f30a39


$Global:clientreq = ConvertFrom-Json @"
{
"redirect_uris" : [ "https://accounts.google.com/o/oauth2/approval" ]
}
"@

# OAuthPS
$CLIENTID      = "127194997596-u2h1uqgu2d05ocgt6i59mpb72pcn5kii.apps.googleusercontent.com"
$CLIENTSECRET  = "hC2iktQD7reOAq4vhWAdPWHG"
$SCOPES        = "https://www.googleapis.com/auth/photoslibrary"
$ERR           = $null
$DEST_ALBUMS   = "C:\Users\zacjordaan\Desktop\albums.csv" #"C:\Users\ueszjv\Desktop\albums.csv"              # csv output file will be created/updated here
$HASH_ALBUMS   = @{} #https://kevinmarquette.github.io/2016-11-06-powershell-hashtable-everything-you-wanted-to-know-about/

<#
$authcode      = $null
$token         = $null
$access_token  = $null
$refresh_token = $null
$token         = $null
#>

# -----------------------------------------------------------------------------
# OAUTH FUNCTIONS
# -----------------------------------------------------------------------------

function GetAuthURL([string]$clientId, [string]$scopes) {
    $hold = "https://accounts.google.com/o/oauth2/auth?client_id=$clientId&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=$scopes&response_type=code";
    return $hold;
}


function ExchangeCode([string]$clientId, [string]$secret, [string]$code){
    
    # Exchange Refresh Token for Access Token
    # Access Tokens have a limited lifetime (approximately 60 minutes) whereas Refresh Tokens last indefinitely, except for the circumstances defined at https://developers.google.com/identity/protocols/OAuth2#expiration
    # The Access Token is what you will hardcode into your script, configuring the script to hit the Google Identity Platform to request a Refresh Token on execution. 

    $grantType   = "authorization_code"
    $redirectURI = "urn:ietf:wg:oauth:2.0:oob";
    $parms       = "code=$code&client_id=$clientId&client_secret=$secret&redirect_uri=$redirectURI&grant_type=$grantType";

    try {
        $response = Invoke-RestMethod -Uri "https://accounts.google.com/o/oauth2/token" -Method Post -Body $parms
    } catch {
        $script:ERR = $_
        Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ 
        Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    }
    return $response
}


function RefreshAccessToken([string]$clientId, [string]$secret, [string]$refreshToken){
    
    # If we have a Refresh Token, Client ID and Client Secret then we can request an Access Token

    $grantType   = "refresh_token"
    $parms       = "client_id=$clientId&client_secret=$secret&refresh_token=$refreshToken&grant_type=$grantType"
    
    try {
        $response = Invoke-RestMethod -Uri https://www.googleapis.com/oauth2/v4/token -Method POST -Body $parms
        return $response.access_token;
    } catch {
        $script:ERR = $_
        Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ 
        Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    }

}

# Alternative from https://monteledwards.com/2017/03/05/powershell-oauth-downloadinguploading-to-google-drive-via-drive-api/
function Get-GAuthToken0 {
    
    Write-Host "Get-GAuthToken()" -ForegroundColor Gray

    $refreshToken  = "1/Jr9jNlg8Pac5JU7utud5YeTopMe_9uUsuLegm57ZMYk" 
    $ClientID      = "127194997596-u2h1uqgu2d05ocgt6i59mpb72pcn5kii.apps.googleusercontent.com"
    $ClientSecret  = "hC2iktQD7reOAq4vhWAdPWHG"
    $grantType     = "refresh_token" 
    $requestUri    = "https://accounts.google.com/o/oauth2/token" 
    $GAuthBody     = "refresh_token=$refreshToken&client_id=$ClientID&client_secret=$ClientSecret&grant_type=$grantType" 
    $GAuthResponse = Invoke-RestMethod -Method Post -Uri $requestUri -ContentType "application/x-www-form-urlencoded" -Body $GAuthBody 

    #Write-Host $GAuthResponse.access_token -ForegroundColor Gray
    return $GAuthResponse.access_token
}

function Get-GAuthToken([string]$clientId, [string]$secret, [string]$refreshToken) {
    
    Write-Host "Get-GAuthToken()" -ForegroundColor Gray

    $grantType     = "refresh_token" 
    $requestUri    = "https://accounts.google.com/o/oauth2/token" 
    $GAuthBody     = "refresh_token=$refreshToken&client_id=$clientId&client_secret=$secret&grant_type=$grantType" 
    $GAuthResponse = Invoke-RestMethod -Method Post -Uri $requestUri -ContentType "application/x-www-form-urlencoded" -Body $GAuthBody 

    #Write-Host $GAuthResponse.access_token -ForegroundColor Gray
    return $GAuthResponse.access_token
}


# WIP!
# https://github.com/globalsign/OAuth-2.0-client-examples/blob/master/PowerShell/Powershell-example.ps1
function GetAuthCode([string]$authurl){

    write-host "GetAuthCode()" -ForegroundColor Gray

    # windows forms dependencies
    # https://blogs.technet.microsoft.com/stephap/2012/04/23/building-forms-with-powershell-part-1-the-form/
    Add-Type -AssemblyName System.Windows.Forms 
    Add-Type -AssemblyName System.Web

    # create window for embedded browser
    $form = New-Object Windows.Forms.Form
    $form.Text = "GetAuthCode()"
    $form.Width = 600
    $form.Height = 800
    $form.StartPosition = "CenterScreen"
    $icon = New-Object system.drawing.icon ("$PSScriptRoot\img\star.ico") #[system.drawing.icon]::ExtractAssociatedIcon($PSHOME + "\powershell.exe")
    $form.Icon = $icon
    
    # add a web browser to the form
    $web = New-Object Windows.Forms.WebBrowser
    $web.Size = $form.ClientSize
    $web.Anchor = "Left,Top,Right,Bottom"
    $form.Controls.Add($web)

    # global for collecting authorization code response
    $Global:redirect_uri = $null

    # add handler for the embedded browser's Navigating event
    $web.add_Navigating({
        write-host "Navigating to: $($_.Url)" -ForegroundColor Cyan
        write-host "Url.Authority:"$_.Url.Authority -ForegroundColor Gray
        write-host "Url.AbsolutePath:"$_.Url.AbsolutePath -ForegroundColor Gray
        
        # detect when browser is about to fetch redirect_uri
        $uri = [uri] $Global:clientreq.redirect_uris[0]

        if($_.Url.Authority -eq $uri.Authority -And $_.Url.AbsolutePath -eq $uri.AbsolutePath) {
            # collect authorization response in a global
            $Global:redirect_uri = $_.Url

            # cancel event and close browser window
            $form.DialogResult = "OK"
            $form.Close()
            $_.Cancel = $true
        }

    })

    # send authorization code request
    write-host "Sending browser to:"
    write-host $authurl -ForegroundColor Yellow
    $web.Navigate($authurl)

    # show browser window, wait for window to close
    if($form.ShowDialog() -ne "OK") {
        write-host "WebBrowser: Canceled" -ForegroundColor Gray
        return
    }
    if(-not $Global:redirect_uri) {
        write-host "WebBrowser: redirect_uri is null" -ForegroundColor Gray
        return
    }


    # decode query string of authorization code response
    $response = [Web.HttpUtility]::ParseQueryString($Global:redirect_uri.Query)
    if(-not $response.Get("code")) {
        write-host "WebBrowser: authorization code is null" -ForegroundColor Gray
        return
    }


}


# -----------------------------------------------------------------------------
# API FUNCTIONS
# -----------------------------------------------------------------------------


function GetAlbums([string]$bearer_token){
#https://developers.google.com/photos/library/guides/list#listing-albums

    write-host "ListAlbums()" -ForegroundColor Gray

    $i = 0
    $nextPageToken = ""
    $headers = @{"Authorization" = "Bearer $bearer_token";} 
    $ht_albums = @{}

    try {

        while($nextPageToken -ne $null -And $i -lt 2){ # <-- SAFETY LIMIT VARIABLE i HERE
            $i++
            #Write-Host $i

            # The default and recommended page size when listing albums is 20 albums, with a maximum of 50 albums. HAS BUG!
            $url = "https://photoslibrary.googleapis.com/v1/albums?pageSize=50"
            if($nextPageToken -ne ""){
                $url += "&pageToken=$nextPageToken"
            }

            # Execute request
            #write-host $url -ForegroundColor Cyan
            $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
            #write-host ($response | ConvertTo-JSON) -ForegroundColor Gray

            $nextPageToken = $response.nextPageToken
            $albums = $response.albums 

            #write-host $i")`t" $albums.Count "Albums returned by this request"
            
            # Print results to console (selected properties only)
            #$albums | Select title, totalMediaItems | Format-Table -auto

            # Add to hashtable
            ForEach($album in $albums){
                #$str = "$($album.title) ($($album.totalMediaItems))"
                $ht_albums.Add($album.id, $album)
            }
        }

    } catch {
        $script:ERR = $_
        Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ -ForegroundColor Red
        Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Red
    }


    write-host "ht_albums contains: $($ht_albums.Count) values" -ForegroundColor Gray
    return $ht_albums
}

function GetAlbumContents([string]$bearer_token, [string]$albumId){

    $i = 0
    $nextPageToken = ""
    $headers = @{"Authorization" = "Bearer $bearer_token";} 
    $ht_mediaItems = @{}

    try {

        while($nextPageToken -ne $null -And $i -lt 2){ # <-- SAFETY LIMIT VARIABLE i HERE
            $i++

            $url = "https://photoslibrary.googleapis.com/v1/mediaItems:search?albumId=$albumId&pageSize=500" #default: 100, max: 500

            if($nextPageToken -ne ""){
                $url += "&pageToken=$nextPageToken"
            }

            # Execute request
            #write-host $url -ForegroundColor Cyan
            $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers
            #write-host ($response | ConvertTo-JSON) -ForegroundColor Gray

            $nextPageToken = $response.nextPageToken
        
            $mediaItems = $response.mediaItems 

            # Add to hashtable
            ForEach($mediaItem in $mediaItems){
                $ht_mediaItems.Add($mediaItem.id, $mediaItem)
            }

            # Print results to console (selected properties only)
            #$mediaItems | Select-Object id, description, mimeType | Format-Table -auto
            #@{N="MediaTypeP";E={$_.mediaMetadata.photo}},
            #https://stackoverflow.com/questions/29595518/is-the-following-possible-in-powershell-select-object-property-subproperty 
          

            # Append (export) results to csv (selected properties only)
            #$albums | Select-Object id, title, totalMediaItems, productUrl | export-csv -NoTypeInformation -append -path $DEST_ALBUMS
            
            
        }

    } catch {
        $script:ERR = $_
        Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ -ForegroundColor Red
        Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Red
    }


    write-host "ht_mediaItems contains: $($ht_mediaItems.Count) values" -ForegroundColor Gray
    return $ht_mediaItems
}







# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------


# Clear screen
Clear-Host


# -----------------------------------------------------------------------------
# OAUTH
# -----------------------------------------------------------------------------

#$authurl  = GetAuthURL $CLIENTID $SCOPES
#GetAuthCode $authurl
#return



# Get OAuth2 Authorization Code
if($authcode -eq $null){
    $authurl  = GetAuthURL $CLIENTID $SCOPES

    write-host "Manually execute this request in your browser and then hardcode the return value to the authcode variable:" -ForegroundColor yellow
    write-host
    write-host $authurl
    write-host

    # Open authurl in the default browser:
    Start-Process $authurl

    return

    $authcode = "4/AADkEBtcQ7c5qJAixCpzz9ygC6Sw32MHhBJaH2HEQ6vP_Cep_Az8D4o" # Code from web browser link above... AFTER PASTING - HIGHLIGHT AND F8 TO SET THE VARIABLE!
}


# Get initial token and Exchange Refresh Token for Access Token
if($token -eq $null){
    write-host "Exchanging Refresh Token for Access Token..." -ForegroundColor yellow
    $token = ExchangeCode $CLIENTID $CLIENTSECRET $authcode
    $access_token = $token.access_token
    $refresh_token = $token.refresh_token


    # Use refresh token to get new access token
    # The access token is used to access an api by sending the access_token parm with any request. 
    # Access tokens are only valid for about an hour after that you will need to request a new one using your refresh_token
    $access_token = RefreshAccessToken $CLIENTID $CLIENTSECRET $refresh_token

    write-host "(refreshed) access_token: $access_token" -ForegroundColor Yellow
}


# Check that we have a valid access token
if($access_token -eq $null){
    Write-Host "Access Token required" -ForegroundColor Red
    return
} 
else{
    #write-host $access_token -ForegroundColor Cyan
    write-host "Access Token OK... I think!" -ForegroundColor Green
    write-host
}


#$access_token = Get-GAuthToken $CLIENTID $CLIENTSECRET $refresh_token #<--WORKS!


# -----------------------------------------------------------------------------
# LIST ALBUMS
# https://developers.google.com/photos/library/guides/list#listing-albums
# -----------------------------------------------------------------------------
if(1 -eq 0){
    $i = 0
    $nextPageToken = ""
    $headers = @{"Authorization" = "Bearer $access_token";} 
    $total_albums_count = 0 #602 Albums in Total as at 05 Jul 2018
    try {


        while($nextPageToken -ne $null -And $i -lt 2){ # <-- SAFETY LIMIT VARIABLE i HERE
            $i++
            #Write-Host $i

            # The default and recommended page size when listing albums is 20 albums, with a maximum of 50 albums. HAS BUG!
            $url = "https://photoslibrary.googleapis.com/v1/albums?pageSize=50"

            if($nextPageToken -ne ""){
                $url += "&pageToken=$nextPageToken"
            }

            # Execute request
            #write-host $url -ForegroundColor Cyan
            $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
            #write-host ($response | ConvertTo-JSON) -ForegroundColor Gray

            $nextPageToken = $response.nextPageToken
        
            $albums = $response.albums 
            write-host $i")`t" $albums.Count "Albums Found"
            $total_albums_count += $albums.Count
            #$albums | Select title, totalMediaItems | Format-Table -auto

            <# Print results to console (selected properties only)
            #$albums | Select title, totalMediaItems | Format-Table -auto
            #>

            #<# Add to hashtable
            ForEach($album in $albums){
                $str = "$($album.title) ($($album.totalMediaItems))"
                $HASH_ALBUMS.Add($album.id, $str)
            }
            #>

            <# Append (export) results to csv (selected properties only)
            $albums | Select-Object id, title, totalMediaItems, productUrl | export-csv -NoTypeInformation -append -path $DEST_ALBUMS
            #>

        }

    } catch {
        $script:ERR = $_
        Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ -ForegroundColor Red
        Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Red
    }


    write-host
    write-host "----------------------------------------" -ForegroundColor Yellow
    write-host $total_albums_count "Albums in Total" -ForegroundColor Yellow
    write-host "----------------------------------------" -ForegroundColor Yellow


    write-host "HASH_ALBUMS contains: $($HASH_ALBUMS.Count) values"
}


# Refresh if necessary???
write-host "Assuming ht_albums already populated" -ForegroundColor Yellow
#$ht_albums = GetAlbums $access_token

<#
foreach($key in $ht_albums.keys)
{
    #$message = '{0} is {1} years old' -f $key, $ageList[$key]
    #Write-Output $message
    $album = $ht_albums[$key]
    $album.title + "($key)"
}
#>
# OR...
<#
# enumerator gives each key/value pair one after another...
$ht_albums.GetEnumerator() | ForEach-Object{
    #$_.key
    #$_.value
    $album = $_.value
    $album.title + "($_.key)"
}
#>

#20170617 Father's Day Metal Forge(AGj1epXRfU_0py7aGdkqoeLtfUXrNRwGUEpZpPe8A_2ZIk2kUT_K)
$albumId = "AGj1epXRfU_0py7aGdkqoeLtfUXrNRwGUEpZpPe8A_2ZIk2kUT_K"

$ht_mediaItems = GetAlbumContents $access_token $albumId
#<#
$i=0
foreach($key in $ht_mediaItems.keys)
{
    $i++
    $mediaItem = $ht_mediaItems[$key]

    write-host $i $mediaItem.mimeType $mediaItem.mediaMetadata.photo
    #$mediaItem.description + "($key)"
    
}
#>


# -----------------------------------------------------------------------------
# LIST LIBRARY CONTENTS
# https://developers.google.com/photos/library/guides/list#listing-library-contents
# * Excludes archived and deleted items
# * Media shared with a user that is not added to the library isn't listed
# -----------------------------------------------------------------------------
if(1 -eq 0){
    $i = 0
    $nextPageToken = ""
    $headers = @{"Authorization" = "Bearer $access_token";} 
    $total_mediaItems_count = 0 
    try {


        while($nextPageToken -ne $null -And $i -lt 2){ # <-- SAFETY LIMIT VARIABLE i HERE
            $i++
            #Write-Host $i

            # The default and recommended page size when listing albums is 20 albums, with a maximum of 50 albums. HAS BUG!
            $url = "https://photoslibrary.googleapis.com/v1/mediaItems:search?pageSize=3"

            if($nextPageToken -ne ""){
                $url += "&pageToken=$nextPageToken"
            }

            # Execute request
            #write-host $url -ForegroundColor Cyan
            $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers
            #write-host ($response | ConvertTo-JSON) -ForegroundColor Gray

            $nextPageToken = $response.nextPageToken
        
            $mediaItems = $response.mediaItems 
            write-host $i")`t" $mediaItems.Count "mediaItems Found"
            $total_mediaItems_count += $mediaItems.Count

            # Print results to console (selected properties only)
            $mediaItems | Select-Object id, description, mimeType | Format-Table -auto
            #@{N="MediaTypeP";E={$_.mediaMetadata.photo}},
            #https://stackoverflow.com/questions/29595518/is-the-following-possible-in-powershell-select-object-property-subproperty 


            ## Add to hashtable
            #ForEach($album in $albums){
            #    $str = "$($album.title) ($($album.totalMediaItems))"
            #    $HASH_ALBUMS.Add($album.id, $str)
            #}
            

            # Append (export) results to csv (selected properties only)
            #$albums | Select-Object id, title, totalMediaItems, productUrl | export-csv -NoTypeInformation -append -path $DEST_ALBUMS

        }

    } catch {
        $script:ERR = $_
        Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ -ForegroundColor Red
        Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Red
    }


    write-host
    write-host "----------------------------------------" -ForegroundColor Yellow
    write-host $total_mediaItems_count "MediaItems in Total" -ForegroundColor Yellow
    write-host "----------------------------------------" -ForegroundColor Yellow


#write-host "HASH_ALBUMS contains: $($HASH_ALBUMS.Count) values"
}




write-host "`nFIN" -ForegroundColor Yellow






#SCRATCHINGS...
<# 

    ForEach($album in $albums){
        
        $objAlbum = [pscustomobject] [ordered] @{
                                                    id = $album.id;
                                                    title = $album.title; 
                                                    productUrl = $album.productUrl; 
                                                    coverPhotoBaseUrl = $album.coverPhotoBaseUrl;  
                                                    isWriteable = $album.isWriteable;
                                                    totalMediaItems = $album.totalMediaItems
                                                    }

        #write-host $album

    }
#>