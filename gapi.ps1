#https://monteledwards.com/2017/03/05/powershell-oauth-downloadinguploading-to-google-drive-via-drive-api/
#https://gist.github.com/LindaLawton/55115de5e8b366be3969b24884f30a39


# OAuthPS
$CLIENTID      = "127194997596-u2h1uqgu2d05ocgt6i59mpb72pcn5kii.apps.googleusercontent.com"
$CLIENTSECRET  = "https://console.developers.google.com/apis/credentials?project=gpm-20180408"
$SCOPES        = "https://www.googleapis.com/auth/photoslibrary"
$ERR           = $null
$DEST_ALBUMS   = "C:\Users\ueszjv\Desktop\albums.csv"              # csv output file will be created/updated here

<#
$authcode      = $null
$token         = $null
$access_token  = $null
$refresh_token = $null
$token         = $null
#>


function GetAuthURL([string]$clientId, [string]$scopes) {
    $hold = "https://accounts.google.com/o/oauth2/auth?client_id=$clientId&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=$scopes&response_type=code";
    return $hold;
}


function ExchangeCode([string]$clientId, [string]$secret, [string]$code){
    
    # Exchange Refresh Token for Access Token�
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









# Clear screen
cls


# -----------------------------------------------------------------------------
# OAUTH
# -----------------------------------------------------------------------------

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

    $authcode = "4/AABG8uwugtQFpoOMJ0D3uZo2x3dVhabB49FkHasPZl7AH25PfDpaiFw" # Code from web browser link above... AFTER PASTING - HIGHLIGHT AND F8 TO SET THE VARIABLE!
}


# Get initial token and Exchange Refresh Token for Access Token�
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
} else{
    write-host $access_token -ForegroundColor Cyan
    write-host "Access Token OK... I think!" -ForegroundColor Green
    write-host
}


#$access_token = Get-GAuthToken $CLIENTID $CLIENTSECRET $refresh_token #<--WORKS!


# -----------------------------------------------------------------------------
# LIST ALBUMS
# https://developers.google.com/photos/library/guides/list#listing-albums
# -----------------------------------------------------------------------------

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
        #$nextPageToken = ""
        #if($nextPageToken -eq ""){
        #    $nextPageToken = $null
        #}
        
        $albums = $response.albums 
        write-host $i")`t" $albums.Count "Albums Found"
        $total_albums_count += $albums.Count
        #$albums | Select title, totalMediaItems | Format-Table -auto

        <# Print results to console (selected properties only)
        #$albums | Select title, totalMediaItems | Format-Table -auto
        #>

        #<# Append (export) results to csv (selected properties only)
        $albums | Select id, title, totalMediaItems, productUrl | export-csv -NoTypeInformation �append �path $DEST_ALBUMS
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




<# SCRATCHINGS

    ForEach($album in $albums){
        
        $objAlbum = [pscustomobject] [ordered] @{
                                                    id = $album.id;
                                                    title = $album.title; 
                                                    productUrl = $album.productUrl; 
                                                    coverPhotoBaseUrl = $album.coverPhotoBaseUrl;  
                                                    isWriteable = $album.isWriteable;
                                                    totalMediaItems = $album.totalMediaItem
                                                    }


        #write-host $album

    }
#>