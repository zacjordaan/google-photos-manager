#https://monteledwards.com/2017/03/05/powershell-oauth-downloadinguploading-to-google-drive-via-drive-api/
#https://gist.github.com/LindaLawton/55115de5e8b366be3969b24884f30a39

#$psISE.CurrentFile.Editor.ToggleOutliningExpansion()
#Or use Ctrl+M to collapse/expand in the ISE

#region GLOBAL SETTINGS

    $Global:clientreq = ConvertFrom-Json "{'redirect_uris' : [ 'https://accounts.google.com/o/oauth2/approval' ]}"

    # OAuthPS
    $CLIENTID      = "127194997596-u2h1uqgu2d05ocgt6i59mpb72pcn5kii.apps.googleusercontent.com"
    $CLIENTSECRET  = "hC2iktQD7reOAq4vhWAdPWHG"
    $SCOPES        = "https://www.googleapis.com/auth/photoslibrary https://picasaweb.google.com/data"
    $ERR           = $null
    $DEST_ALBUMS   = "C:\Users\zacjordaan\Desktop\albums.csv" #"C:\Users\ueszjv\Desktop\albums.csv"              # csv output file will be created/updated here
    $REFRESH_TOKEN = "1/PxJtMpSmxjoMJN7Vnfi2o5TWACWwMSNkmuC6jZIqOq1V__5zsJTXvEd_ccLGAudk"

    #https://kevinmarquette.github.io/2016-11-06-powershell-hashtable-everything-you-wanted-to-know-about/
    $HASH_ALBUMS   = @{}


    #$authcode      = $null
    #$token         = $null
    #$access_token  = $null
    #$refresh_token = $null
    #$token         = $null

#endregion

#region OAUTH FUNCTIONS
# -----------------------------------------------------------------------------

    <#
    Step 1: Ask for access
    https://accounts.google.com/o/oauth2/auth?client_id={clientid}.apps.googleusercontent.com&redirect_uri={From console}&scope=openid%20email&response_type=code
    This just displays the window asking them to approve you. Once the user has approved access you get a one time Authentication Code.

    Step 2: Exchange Authentication Code for AccessToken and RefreshToken. 
    (Note this needs to be sent as a HTTP POST not a HTTP Get)
    https://accounts.google.com/o/oauth2/tokencode={Authentication Code from step 1}&client_id={ClientId}.apps.googleusercontent.com&client_secret={ClientSecret}&redirect_uri=={From console}&grant_type=authorization_code
    you should get a JSon string back looking something like this:
    {
    "access_token" : "ya29.1.AADtN_VSBMC2Ga2lhxsTKjVQ_ROco8VbD6h01aj4PcKHLm6qvHbNtn-_BIzXMw",
    "token_type" : "Bearer",
    "expires_in" : 3600,
    "refresh_token" : "1/J-3zPA8XR1o_cXebV9sDKn_f5MTqaFhKFxH-3PUPiJ4"
    }

    Now you can take that Access_token and use it to make your requests.
    But access tokens are only good for 1 hour and then they expire before that time you need to use the Refresh_token to get a new access token. 
    Also if you are going to want to access your users data again you should save the  refresh_token some place that will enable you to always access their data.

    Step 3: Use Refreshtoken
    https://accounts.google.com/o/oauth2/tokenclient_id={ClientId}.apps.googleusercontent.com&client_secret={ClientSecret}&refresh_token={RefreshToken from step 2}&grant_type=refresh_token
    This time you will only get the Access token back, because your refreshtoken is good until the user removes authentication or you haven't used it for 6 months.
    {
    "access_token" : "ya29.1.AADtN_XK16As2ZHlScqOxGtntIlevNcasMSPwGiE3pe5ANZfrmJTcsI3ZtAjv4sDrPDRnQ",
    "token_type" : "Bearer",
    "expires_in" : 3600
    }
    You can find more detailed information on this here: 
    Google 3 Legged oauth2 flow: http://www.daimto.com/google-3-legged-oauth2-flow/
    #>

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

    function Get-GAuthToken0 {
    # Alternative from https://monteledwards.com/2017/03/05/powershell-oauth-downloadinguploading-to-google-drive-via-drive-api/
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

    function GetAuthCode([string]$authurl){
    # https://github.com/globalsign/OAuth-2.0-client-examples/blob/master/PowerShell/Powershell-example.ps1    

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
#endregion

#region API FUNCTIONS
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

    function GetMediaItems([string]$bearer_token, [string]$albumId){

        $i = 0
        $nextPageToken = ""
        $headers = @{"Authorization" = "Bearer $bearer_token";} 
        $ht_mediaItems = @{}

        try {

            while($nextPageToken -ne $null -And $i -lt 5){ # <-- SAFETY LIMIT VARIABLE i HERE
                $i++

                $url = "https://photoslibrary.googleapis.com/v1/mediaItems:search?pageSize=500" #default: 100, max: 500

                if($albumId -ne $null){
                    $url += "&albumId=$albumId"
                }

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
#endregion




# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------


# Clear screen
Clear-Host

#region OAUTH
# -----------------------------------------------------------------------------


# Step 1: Ask for access (Get OAuth2 Authorization Code)
if($authcode -eq $null){

    
    #https://accounts.google.com/o/oauth2/auth?client_id=127194997596-u2h1uqgu2d05ocgt6i59mpb72pcn5kii.apps.googleusercontent.com&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=https://www.googleapis.com/auth/photoslibrary https://picasaweb.google.com/data&response_type=code
    # This just displays the window asking for approval. Once user has approved access you get a one time Authentication Code.

    $authurl  = GetAuthURL $CLIENTID $SCOPES
    #might have to urlencode to replace scopes spaces with %20 ?

    write-host "Manually execute this request in your browser and then hardcode the return value to the authcode variable:" -ForegroundColor yellow
    write-host
    write-host $authurl
    write-host

    # Open authurl in the default browser:
    Start-Process $authurl

    return

    $authcode = "4/AABgNL9JLBVh45dTIyh1q07E7SzpbVTMO3f0UeIXEbxs449te5dH7Z0" # Code from web browser link above... AFTER PASTING - HIGHLIGHT AND F8 TO SET THE VARIABLE!
}


# Step 2 & 3: Exchange Authentication Code for AccessToken and RefreshToken.
if($access_token -eq $null){

    # (Note this needs to be sent as a HTTP POST not a HTTP Get)
    #https://accounts.google.com/o/oauth2/tokencode={Authentication Code from step 1}&client_id={ClientId}.apps.googleusercontent.com&client_secret={ClientSecret}&redirect_uri=={From console}&grant_type=authorization_code
    
    # you should get a JSon string back looking something like this:
    #{
    #"access_token" : "ya29.1.AADtN_VSBMC2Ga2lhxsTKjVQ_ROco8VbD6h01aj4PcKHLm6qvHbNtn-_BIzXMw",
    #"token_type" : "Bearer",
    #"expires_in" : 3600,
    #"refresh_token" : "1/J-3zPA8XR1o_cXebV9sDKn_f5MTqaFhKFxH-3PUPiJ4"
    #}

    write-host "Exchanging Authentication Code for AccessToken..." -ForegroundColor yellow

    write-host "WAIT: Try using just the refresh_token?" -ForegroundColor yellow
    return

    $token = ExchangeCode $CLIENTID $CLIENTSECRET $authcode
    $access_token = $token.access_token
    $REFRESH_TOKEN = $token.refresh_token #1/PxJtMpSmxjoMJN7Vnfi2o5TWACWwMSNkmuC6jZIqOq1V__5zsJTXvEd_ccLGAudk #<-- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    # Now you can use $access_token to make API requests.
    # However, access tokens are only good for 1 hour and then they expire, so before that time you need to use $REFRESH_TOKEN to get a NEW access token.
    # Also if you are going to want to access your users data again you should save the refresh_token some place that will enable you to always access their data.

    #Step 3: Use Refreshtoken
    #https://accounts.google.com/o/oauth2/tokenclient_id={ClientId}.apps.googleusercontent.com&client_secret={ClientSecret}&refresh_token={RefreshToken from step 2}&grant_type=refresh_token
    #This time you will only get the Access token back, because your refreshtoken is good until the user removes authentication or you haven't used it for 6 months.
    #{
    #"access_token" : "ya29.1.AADtN_XK16As2ZHlScqOxGtntIlevNcasMSPwGiE3pe5ANZfrmJTcsI3ZtAjv4sDrPDRnQ",
    #"token_type" : "Bearer",
    #"expires_in" : 3600
    #}
    #You can find more detailed information on this here: 
    #Google 3 Legged oauth2 flow: http://www.daimto.com/google-3-legged-oauth2-flow/


    # Use refresh token to get new access token
    # The access token is used to access an api by sending the access_token parm with any request. 
    # Access tokens are only valid for about an hour after that you will need to request a new one using your refresh_token
    $access_token = RefreshAccessToken $CLIENTID $CLIENTSECRET $REFRESH_TOKEN

    write-host "(refreshed) access_token: $access_token" -ForegroundColor Yellow
}


# Check that we have a valid access token
if($access_token -eq $null){
    Write-Host "Access Token required" -ForegroundColor Red
    return
} 
else{

    # Google's authorization server responds to the request with a JSON object that either describes the token or contains an error message.
    $obj_access_token = Invoke-RestMethod "https://www.googleapis.com/oauth2/v3/tokeninfo?access_token=$access_token"
    
    #{
    #  "aud":"8819981768.apps.googleusercontent.com",
    #  "user_id":"123456789",
    #  "scope":"https://www.googleapis.com/auth/drive.metadata.readonly",
    #  "expires_in":436
    #}

    # azp        : ???
    # aud        : The application that is the intended user of the access token. 
    # expires_in : The number of seconds left before the token becomes invalid.
    # scope      : A space-delimited list of scopes that the user granted access to. The list should match the scopes specified in your authorization request in step 1.
    # userid     : This value lets you correlate profile information from multiple Google APIs. It is only present in the response if you included the profile scope in your request in step 1. 
    #              The field value is an immutable identifier for the logged-in user that can be used to create and manage user sessions in your application.
    #              The identifier is the same regardless of which client ID is used to retrieve it. This enables multiple applications in the same organization to correlate profile information.


    if($obj_access_token -eq $null -Or $obj_access_token -eq ""){
        Write-Host "Access Token could not be validated" -ForegroundColor Red
        return
    
    } elseif($obj_access_token.aud -ne $CLIENTID){
        Write-Host "INVALID Access Token" -ForegroundColor Red
        return
    }

    $ts =  [timespan]::fromseconds($obj_access_token.expires_in)
    write-host "Access Token OK (expires in $ts)" -ForegroundColor Green
    write-host
    
    if($ts.Minutes -lt 5){
        $access_token = RefreshAccessToken $CLIENTID $CLIENTSECRET $REFRESH_TOKEN
    }
}




#$access_token = Get-GAuthToken $CLIENTID $CLIENTSECRET $REFRESH_TOKEN

#endregion


# -----------------------------------------------------------------------------
# ALBUMS
# https://developers.google.com/photos/library/guides/list#listing-albums
# -----------------------------------------------------------------------------
if(1 -eq 0){

    # Refresh if necessary???
    #write-host "Assuming ht_albums already populated" -ForegroundColor Yellow
    $ht_albums = GetAlbums $access_token

    foreach($key in $ht_albums.keys)
    {
        $album = $ht_albums[$key]
        $album.title + "($key)"
    }

    # OR...
    # enumerator gives each key/value pair one after another...
    #$ht_albums.GetEnumerator() | ForEach-Object{
    #    #$_.key
    #    #$_.value
    #    $album = $_.value
    #    $album.title + "($_.key)"
    #}

}

# -----------------------------------------------------------------------------
# ALBUMS (PICASA)
# https://developers.google.com/picasa-web/docs/3.0/reference#Parameters
# -----------------------------------------------------------------------------
if(1 -eq 1){

    write-host "PICASA: ListAlbums()" -ForegroundColor Yellow

    $headers = @{"Authorization" = "Bearer $access_token"}
    $url = "https://picasaweb.google.com/data/feed/api/user/default?&kind=album&max-results=10"
    write-host $url -ForegroundColor Cyan


    try {
        # Execute request
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
        $i = 0
        #$response | Get-Member
        $results = foreach($album in $response){
            #Write-Host $album.id
            #Write-Host "$($album.id.Split(" ")[1])`t$($album.title.InnerText)`t$($album.numphotos.ToString())"
            "$($album.id.Split(" ")[1])`t$($album.title.InnerText)`t$($album.numphotos.ToString())"
        }
        $results | ft
    } catch {
        $script:ERR = $_
        Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ -ForegroundColor Red
        Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Red
    }

}


# -----------------------------------------------------------------------------
# ALBUM CONTENTS
# -----------------------------------------------------------------------------
if(1 -eq 0){

    $albumId = "AGj1epXRfU_0py7aGdkqoeLtfUXrNRwGUEpZpPe8A_2ZIk2kUT_K" #20170617 Father's Day Metal Forge

    $headers = @{"Authorization" = "Bearer $access_token";} 
    $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
    $ht_mediaItems = GetMediaItems $access_token $albumId

    $i=0
    foreach($key in $ht_mediaItems.keys)
    {
        $i++
        $mediaItem = $ht_mediaItems[$key]

        write-host $i $mediaItem.mimeType $mediaItem.mediaMetadata.photo
        #Write-Host $mediaItem.mediaMetadata.creationTime
        #return
        #$mediaItem.description + "($key)"
    
    }

}

# -----------------------------------------------------------------------------
# ALBUM CONTENTS (PICASA)
# -----------------------------------------------------------------------------
if(1 -eq 0){

    $albumId = "AGj1epXRfU_0py7aGdkqoeLtfUXrNRwGUEpZpPe8A_2ZIk2kUT_K" #20170617 Father's Day Metal Forge

    write-host "Trying Picasa API" -ForegroundColor Yellow

    #$url = "https://picasaweb.google.com/data/feed/api/user/default/albumid/$albumId"
    #$url = "https://picasaweb.google.com/data/feed/api/user/zacjordaan/albumid/$albumId"
    
    # last 10 photos uploaded by userID
    $url = "https://picasaweb.google.com/data/feed/api/user/default?kind=photo&max-results=10"

    # Partial query
    #$url = "https://picasaweb.google.com/data/feed/api/default/photosapi?kind=album&v=2.0&fields=entry(title,gphoto:numphotos,media:group(media:thumbnail),link[@rel='http://schemas.google.com/g/2005#feed'](@href))"

    https://picasaweb.google.com/data/feed/api/user/default?kind=album

    write-host $url -ForegroundColor Cyan

    $headers = @{"Authorization" = "Bearer $access_token";"GData-Version" = "3"} 
    $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers

    return



    $ht_mediaItems = GetMediaItems $access_token $albumId

    $i=0
    foreach($key in $ht_mediaItems.keys)
    {
        $i++
        $mediaItem = $ht_mediaItems[$key]

        write-host $i $mediaItem.mimeType $mediaItem.mediaMetadata.photo
        #Write-Host $mediaItem.mediaMetadata.creationTime
        #return
        #$mediaItem.description + "($key)"
    
    }


}



# -----------------------------------------------------------------------------
# LIBRARY CONTENTS
# https://developers.google.com/photos/library/guides/list#listing-library-contents
# * Excludes archived and deleted items
# * Media shared with a user that is not added to the library isn't listed
# -----------------------------------------------------------------------------
if(1 -eq 0){

    $albumId = $null
    $ht_mediaItems = GetMediaItems $access_token $albumId #<-- temp disabled

    $i=0
    foreach($key in $ht_mediaItems.keys)
    {
        $i++
        $mediaItem = $ht_mediaItems[$key]

        #write-host $i $mediaItem.mimeType $mediaItem.mediaMetadata.photo
        Write-Host $mediaItem.MediaMetadata

        #return
        #$mediaItem.description + "($key)"
    
    }

}




write-host "`nFIN" -ForegroundColor Yellow