$Global:clientreq = ConvertFrom-Json "{'redirect_uris' : [ 'https://accounts.google.com/o/oauth2/approval' ]}"

# OAuthPS
$CLIENTID      = "127194997596-u2h1uqgu2d05ocgt6i59mpb72pcn5kii.apps.googleusercontent.com"
$CLIENTSECRET  = "ZZZ"
$SCOPES        = "https://www.googleapis.com/auth/photoslibrary https://picasaweb.google.com/data"
$ACCESS_TOKEN  = $null
$REFRESH_TOKEN = $null
$ERR           = $null
$DEST          = "C:\Users\ueszjv\Desktop\albums.csv"
#$DEST          = "C:\Users\zacjordaan\Desktop\albums.csv"






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

    function GetAuthCode([string]$authurl){
    # https://github.com/globalsign/OAuth-2.0-client-examples/blob/master/PowerShell/Powershell-example.ps1    

        write-host "GetAuthCode()" -ForegroundColor Gray

        <# Testing
        $authurl = "https://accounts.google.com/o/oauth2/auth?client_id=127194997596-u2h1uqgu2d05ocgt6i59mpb72pcn5kii.apps.googleusercontent.com&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=https://www.googleapis.com/auth/photoslibrary https://picasaweb.google.com/data&response_type=code"
        #>

        # windows forms dependencies
        Add-Type -AssemblyName System.Windows.Forms 
        Add-Type -AssemblyName System.Web

        # create form for embedded browser
        $form = New-Object Windows.Forms.Form
        $form.Text = "GetAuthCode()"
        $form.Width = 600
        $form.Height = 800
        $form.StartPosition = "CenterScreen"
        $icon = New-Object system.drawing.icon ("$PSScriptRoot\img\star.ico") #[system.drawing.icon]::ExtractAssociatedIcon($PSHOME + "\powershell.exe")
        $form.Icon = $icon
    
        # add a web browser to form
        $web = New-Object Windows.Forms.WebBrowser
        $web.Size = $form.ClientSize
        $web.Anchor = "Left,Top,Right,Bottom"
        $form.Controls.Add($web)

        # init global variable for authorization code response
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
        $response

        if(-not $response.Get("code")) {
            write-host "WebBrowser: authorization code is null" -ForegroundColor Gray
            return
        }

        return $response.Get("code");

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

    function CheckToken([string]$token){
        
        <#
        .SYNOPSIS
        Verify the validity of an OAuth 2.0 Access Token.

        .DESCRIPTION
        Submit a token to Google's authorization server which responds to the request with a JSON object that either describes the token or contains an error message.
        {
          "aud"        : "8819981768.apps.googleusercontent.com",
          "user_id"    : "123456789",
          "scope"      : "https://www.googleapis.com/auth/drive.metadata.readonly",
          "expires_in" : 436
        }
        azp        : ???
        aud        : The application that is the intended user of the access token. 
        expires_in : The number of seconds left before the token becomes invalid.
        scope      : A space-delimited list of scopes that the user granted access to. The list should match the scopes specified in your authorization request in step 1.
        userid     : This value lets you correlate profile information from multiple Google APIs. It is only present in the response if you included the profile scope in your request in step 1. 
                     The field value is an immutable identifier for the logged-in user that can be used to create and manage user sessions in your application.
                     The identifier is the same regardless of which client ID is used to retrieve it. This enables multiple applications in the same organization to correlate profile information.

        .EXAMPLE
        $mytoken = CheckToken $access_token

        .PARAMETER access_token
        The token to verify.
        #>

        write-host "CheckToken()" -ForegroundColor Gray
        
        $obj_token_info = Invoke-RestMethod "https://www.googleapis.com/oauth2/v3/tokeninfo?access_token=$token"
    
        if($obj_token_info -eq $null -Or $obj_token_info -eq ""){
            Write-Host "Access Token could not be validated" -ForegroundColor Red
            return $null
        }
        elseif($obj_token_info.aud -ne $CLIENTID)
        {
            Write-Host "INVALID Access Token" -ForegroundColor Red
            return $null
        }
        else{
            return $obj_token_info
        }

    }
    

# -----------------------------------------------------------------------------
#endregion

#region API FUNCTIONS
# -----------------------------------------------------------------------------

    function Get-Google-Albums([string]$access_token){
        write-host "Get-Google-Albums()" -ForegroundColor Gray
        
        <# testing
        write-host "{Hardcoded testing parameters in effect}" -ForegroundColor Yellow
        $access_token = "ya29.Glz2Bc71SyOXT-7sXsuDGD-_3QGwAOR34rJTp8J0Xqfr9tGkVMbkhQnhNNU6Du5Aa59AxEPwlGmDoatyLBgfMGOYBtPGS6yWqw1dFOMA9koTf7L-y7Q3Kbtfwa-JGg"
        #>

        $headers       = @{"Authorization" = "Bearer $access_token"}
        $nextPageToken = ""
        $url           = "https://photoslibrary.googleapis.com/v1/albums?pageSize=50"
        $fields        = ""
        $google_albums = $null
 
        try {
            $thisurl = $url
            while($nextPageToken -ne $null){
                if($nextPageToken -ne $null){ $thisurl = $url + "&pageToken=$nextPageToken"; }
                $response      = Invoke-RestMethod -Uri $thisurl -Method Get -Headers $headers
                $nextPageToken = $response.nextPageToken
                $google_albums += $response.albums
            }
        } catch {
            $script:ERR = $_
            Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ -ForegroundColor Red
            Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Red
        }

        return $google_albums

        #https://developers.google.com/photos/library/guides/performance-tips
        #https://www.googleapis.com/demo/v1?key=YOUR-API-KEY&fields=kind,items(title,characteristics/length)
    }

    function Get-Google-Album-Contents([string]$access_token, [string]$google_album_id){
        write-host "Get-Google-Album-Contents()" -ForegroundColor Gray
        
        <# testing
        write-host "{Hardcoded testing parameters in effect}" -ForegroundColor Yellow
        $access_token    = "ya29.Glz2Bc71SyOXT-7sXsuDGD-_3QGwAOR34rJTp8J0Xqfr9tGkVMbkhQnhNNU6Du5Aa59AxEPwlGmDoatyLBgfMGOYBtPGS6yWqw1dFOMA9koTf7L-y7Q3Kbtfwa-JGg"
        $google_album_id = "AGj1epVPjGrcUZB_qcbUfzIoKaJIOryIaX6V2xbDzyofiOLoRIW2"
        #>

        $headers               = @{"Authorization" = "Bearer $access_token"}
        $nextPageToken         = ""
        $url                   = "https://photoslibrary.googleapis.com/v1/mediaItems:search?albumId=$google_album_id&pageSize=500"
        $fields                = "id,description,productUrl,baseUrl,mimeType,mediaMetadata(creationTime,photo/cameraMake)"
        $google_album_contents = $null
 
        try {
            $thisurl = $url
            while($nextPageToken -ne $null){
                if($nextPageToken -ne $null){ $thisurl = $url + "&pageToken=$nextPageToken"; }
                $response = Invoke-RestMethod -Uri $thisurl -Method Post -Headers $headers
                $nextPageToken = $response.nextPageToken
                $google_album_contents += $response.mediaItems
            }
        } catch {
            $script:ERR = $_
            Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ -ForegroundColor Red
            Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Red
        }

        return $google_album_contents
    }

    function Get-Google-MediaItem([string]$access_token, [string]$media_item_id){
    
        <# testing
        write-host "{Hardcoded testing parameters in effect}" -ForegroundColor Yellow
        $access_token  = "ya29.Glz2BXWFTjIVt_s0VYTEs3IlaK_78ylK32RznXZQl4G20BPWxh-hoQ7lKCH_PnbV4UdhQy6zgA2ZR0JI-8bcQ4AgnK9iuwnqP2sJ0kwYUHCqKiRTVhLH6_DauIIxZA"
        $media_item_id = "AGj1epXSDBXR0BF9uFxsGA09SS3hMliL9EvKjkJ-MW3B45xefgPSgmxmwcmoOoy5JDrpv8PQO0TwhwI"
        #>

        $headers       = @{"Authorization" = "Bearer $access_token"}
        $url           = "https://photoslibrary.googleapis.com/v1/mediaItems/$($media_item_id)"
        $fields        = ""
        $media_item    = $null
 
        try {
            $media_item   = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
        } catch {
            $script:ERR = $_
            Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ -ForegroundColor Red
            Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Red
        }
    
        
        return $media_item
    }

    function Get-Google-Filename([string]$access_token, [string]$base_url){
        #write-host "Get-Google-Filenames('$($access_token.substring(0,3))...', '$($base_url.substring(0,4))...')" -ForegroundColor Gray

        #https://developers.google.com/photos/library/guides/access-media-items#get-media-item
        
        <# testing
        write-host "{Hardcoded testing parameters in effect}" -ForegroundColor Yellow
        $access_token = "ya29.Glz2BXWFTjIVt_s0VYTEs3IlaK_78ylK32RznXZQl4G20BPWxh-hoQ7lKCH_PnbV4UdhQy6zgA2ZR0JI-8bcQ4AgnK9iuwnqP2sJ0kwYUHCqKiRTVhLH6_DauIIxZA"
        $base_url     = "https://lh3.googleusercontent.com/lr/AJ_cxPYZvpVE3vfa1E5vHoujli7vjpGY5dDLUtD5w2p0cQhcETM7Ezl9f7IBKZ-L6uDD5gTl5vNALRhXQ95FQwgXiYvXCFWaSGmXo7D3-48ICmH5O02Z15GZr-MzT6RuHXmLx7FNYGQSesP7VKtDwGdgrAj1ogS46OAaWVelIjJ-SQvcivURT8G7biU6w3ILZzb4hBo6yYVapYSshSJ62CcJZRLmZz9Csf4HSVjzOKfbDm_4L8lTqh_YqIMt2C0rtLKVI7zjzUMKyXA6EK-wnlXsOI-3VsaK2-u4QshhdrTiyobQ8w7-FplTeRUoRS37Kgyr-tDBpMH_8sgoR8ruxtI6hiV2HkQSqwbISiRPD3kBYlGz_c0IWdYpEwUoAmPwf3r9Ye_LpYEE67apWkLmDAOitQSSnvE6tT3TEQwG-RDjtvXd0kj_HFBN79UWwW9ZeWvh_WS_yB4A19KnF4IqXzFN_wJX351_iCnyOJI8PT5V8rLJ9wpY5eBaCMbJgKUtZWVqdzZAAB0TYuoNopwUcN-Nv3m0hF5gZHP-q2BgwY8aj4VTIDkgExAy3lw009kkdn02LkfGOiAAvJ7t5hVyApvWmfWvZu7jtMT3CE5riRHbNUwGc5HhVjOicCugmwhTujaUxG-uQONOJsP6bH-8WVqD6Oh_7rgfBgPgqj2oYOJSCR7WFxKdCOyV5Rer8FdJeMt2vEUtb4SYn9DmABopFRVOn8KcMggXP2X-A4v0jKq_awL1CbsN6gZD7OUc3ZEFsDiYA4doxAk_ZNrfBlcic2_EfAQIbynKvSpKyD10wd5fAWUxnIZbumxhiVRfDA-aeZGgnXVKwzc"
        #>

        $headers      = @{"Authorization" = "Bearer $access_token"}

        #Warning: Don't use the base URL without specifying a maximum width and height or download parameter.
        # Here I'm pulling images at 1x1 pixels since I have to pull them in order to access the response header via web-request instead of rest-request!
        $url          = $base_url + "=w1-h1"
        $media_item   = $null
        $filename     = $null
 
        #write-host $url -ForegroundColor cyan
        #Start-Process $url # open in browser
 
        try {
            $media_item = Invoke-WebRequest -Uri $url -Method Get #-Headers $headers
            $filename   = ([System.Net.Mime.ContentDisposition]$media_item.Headers.'Content-Disposition').FileName

        } catch {
            $script:ERR = $_
            Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ -ForegroundColor Red
            Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Red
        }

        return $filename

    }

# -----------------------------------------------------------------------------
#endregion


 



#################################################################
# MAIN
#################################################################


# Clear screen
Clear-Host

# OAUTH

if($ACCESS_TOKEN -eq $null -and $REFRESH_TOKEN -eq $null){
    Write-Host "OAuthorization required" -ForegroundColor Red

    $url = "https://accounts.google.com/o/oauth2/auth?client_id=$CLIENTID&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=$SCOPES&response_type=code";
    GetAuthCode $url
}


#######################################
return
#######################################







if($access_token -eq $null){
    
    Write-Host "Access Token required" -ForegroundColor Red

    # We don't have an access token but maybe we do have a refresh token?

    if($REFRESH_TOKEN -ne $null){
        Write-Host "Refreshing Access Token..." -ForegroundColor Yellow
        $access_token = RefreshAccessToken $CLIENTID $CLIENTSECRET $REFRESH_TOKEN
        write-host "(refreshed) access_token: $access_token" -ForegroundColor Yellow
    }
    else{

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

    }

}








# Check that we have a valid access token (and refresh if necessary)
$obj_token_info = CheckToken $access_token
$ts =  [timespan]::fromseconds($obj_token_info.expires_in)
write-host "Access Token OK... expires in $ts" -ForegroundColor Green
if($ts.Minutes -lt 5){
    $access_token = RefreshAccessToken $CLIENTID $CLIENTSECRET $REFRESH_TOKEN
}






return


#$picasa_albums = $null;
#$google_albums = $null;

if($picasa_albums -eq $null){ 
    $picasa_albums = Get-Picasa-Albums $access_token 
}

if($google_albums -eq $null){ 
    $google_albums = Get-Google-Albums $access_token 
}


write-host "picasa_albums: $($picasa_albums.Count)" -ForegroundColor Gray
write-host "google_albums: $($google_albums.Count)" -ForegroundColor Gray
write-host
return

# $picasa_albums --> $parsed_picasa_albums
<# 
$parsed_picasa_albums = $picasa_albums | 
    #Get-Random -Count 20 | 
        Sort-Object -Property @{Expression={$_.title.'#text'}} |
            ForEach-Object{$counter = 1}{ [PSCustomObject]@{ idx=$counter; title=$_.title.'#text'; numphotos=$_.numphotos; id=$_.id[1]; };$counter++ } #| 
                #Select-Object -Property idx, title, @{N='num';E={$_.numphotos}} #-First 5 |
                #Select-Object -Last 5 |
                    #Format-Table -auto
                    #Export-CSV -NoTypeInformation -Path "C:\Users\ueszjv\Desktop\albums_picasa.csv"

#$parsed_picasa_albums
#return
#>

# $google_albums --> $parsed_google_albums
<#
$parsed_google_albums = $google_albums | 
    #Get-Random -Count 20 | 
        Sort-Object -Property @{Expression={$_.title}} |
            ForEach-Object{$counter = 1}{ [PSCustomObject]@{ idx=$counter; title = $_.title; totalMediaItems = $_.totalMediaItems; id = $_.id; productUrl = $_.productUrl };$counter++ } #| 
                #Select-Object -Property idx, title, @{N='num';E={$_.totalMediaItems}} #-First 5 |
                #Select-Object -Last 5 |
                    #Format-Table -auto
                    #Export-CSV -NoTypeInformation -Path "C:\Users\ueszjv\Desktop\albums_google.csv"

#$parsed_google_albums
#return

#>

# What albums are in Google that are not in Picasa, or vice-versa?
<#
$a = $parsed_picasa_albums | Select-Object -Property title, @{N='myNumPhotos';E={$_.numphotos}} #-Last 5         | Format-Table -auto
$b = $parsed_google_albums | Select-Object -Property title, @{N='myNumPhotos';E={$_.totalMediaItems}} #-Last 5   | Format-Table -auto

Compare-Object -ReferenceObject $a -DifferenceObject $b
#$z = Compare-Object -ReferenceObject $a -DifferenceObject $b -includeEqual
#>




#$picasa_albums | where { $_.title.'#text' -eq "20170100" } #works
#$picasa_albums | where { $_.id[1] -eq "6401334202790966817" } #works



# -----------------------------------------
# Compare an album in Picasa against Google
# -----------------------------------------
# $picasa_album_contents = $null;
# $google_album_contents = $null;

# Zac & Melanie's Engagement (20)
$picasa_album_id = "5356380535990121441"
$google_album_id = "AGj1epVPjGrcUZB_qcbUfzIoKaJIOryIaX6V2xbDzyofiOLoRIW2"


# Auto Backup (59258)
#$picasa_album_id = "1000000421995119"
#$album = $picasa_albums | where { $_.id -eq $picasa_album_id }

# lookup album name from id
#$picasa_album_name = ($picasa_albums | where { $_.id[1] -eq $picasa_album_id }).name #hmmmm
$picasa_album_name = ($picasa_albums | where { $_.id[1] -eq $picasa_album_id }).title.'#text'
$google_album_name = ($google_albums | where { $_.id -eq $google_album_id }).title



if($picasa_album_contents -eq $null){ 
    $picasa_album_contents = Get-Picasa-Album-Contents $access_token $picasa_album_id 
}


if($google_album_contents -eq $null){ 
    $google_album_contents = Get-Google-Album-Contents $access_token $google_album_id 
}

write-host "Picasa Album: $picasa_album_name ($($picasa_album_contents.Count))" -ForegroundColor Green
write-host "Google Album: $google_album_name ($($google_album_contents.Count))" -ForegroundColor Green


<#
#$picasa_album_contents[0].title.'#text'
$picasa_album_contents | 
    #Get-Random -Count 2 | 
        #Sort-Object -Property @{Expression={[float]$_.position}} |
            ForEach-Object{
                            $counter = 1
                          }{ 
                            [PSCustomObject] @{
                                            idx     = $counter;
                                            title   = $_.title.'#text'
                                            albumid = $_.albumid;
                                            pos     = $_.position;
                                            id      = $_.id[1];
                                            };
                            $counter++ 
                            } | 
                ##Select-Object -Property idx, title, @{N='num';E={$_.totalMediaItems}} #-First 5 |
                #Sort-Object -Property $_.title |
                #Select-Object -First 2 |
                    #Format-List
                    Format-Table -auto


#$photo = $picasa_album_contents | where { $_.id[1] -eq "6568406794732382386" }
#$photo = $picasa_album_contents | where { $_.id[1] -eq "5356386333976948930" }
#$photo.title.'#text'
#>

<#
#$parsed_google_album_contents = 
$google_album_contents | 
    #Get-Random -Count 2 | 
        #Sort-Object -Property @{Expression={[float]$_.id}} |
            ForEach-Object{ 
                            $counter  = 1;
                            $filename = "bbb"
                          }{
                            [PSCustomObject] @{
                                              idx        = $counter;
                                              #productUrl = $_.productUrl;
                                              #baseUrl    = $_.baseUrl;
                                              fileName   = Get-Google-Filename $access_token $_.baseUrl;
                                              mimeType   = $_.mimeType;
                                              id         = $_.id;
                                              };
                            $counter++ 
                          } | 
                ##Select-Object -Property idx, title, @{N='num';E={$_.totalMediaItems}} #-First 5 |
                #Sort-Object -Property $_.fileName |
                #Select-Object -First 2 |
                    #Format-List
                    Format-Table -auto
#>

#$parsed_google_album_contents


write-host "`nFIN" -ForegroundColor Yellow



<#
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

    function GetAlbums_Google([string]$bearer_token, [int]$maxresults){
        #https://developers.google.com/photos/library/guides/list#listing-albums

        write-host "GetAlbums_Google()" -ForegroundColor Gray

        $i = 0
        $nextPageToken = ""
        $headers = @{"Authorization" = "Bearer $bearer_token";} 
        $ht_albums = @{}

        try {

            while($nextPageToken -ne $null -And ($i -lt 2 -Or $maxresults -eq 0)){ # <-- SAFETY LIMIT VARIABLE i HERE
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


        #write-host "ht_albums contains: $($ht_albums.Count) values" -ForegroundColor Gray
        write-host $ht_albums.Count -ForegroundColor Gray
        return $ht_albums
    }

    function GetAlbums_Picasa([string]$bearer_token, [int]$maxresults){
        write-host "GetAlbums_Picasa()" -ForegroundColor Gray

        $headers = @{"Authorization" = "Bearer $bearer_token"}
        $url = "https://picasaweb.google.com/data/feed/api/user/default?&kind=album"
        if($maxresults -ne 0){ $url += "&max-results=$maxresults"; }

        $ht_albums_picasa = @{}

        try {
            $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
            $i = 0

            foreach($album in $response){
                $ht_albums_picasa.Add($album.id.Split(" ")[1].ToString(), $album)
            }

            $results = foreach($album in $response){
                #Write-Host "$($album.id.Split(" ")[1])`t$($album.title.InnerText)`t$($album.numphotos.ToString())"
                #"$($album.id.Split(" ")[1])`t$($album.title.InnerText)`t$($album.numphotos.ToString())"

                $ht_albums_picasa.Add($album.id.Split(" ")[1].ToString(), $album)
                #$ht_albums_picasa.Add($album.id, $album)
            }
            $results | ft

        } catch {
            $script:ERR = $_
            Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ -ForegroundColor Red
            Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Red
        }


        #write-host "ht_albums_picasa contains: $($ht_albums_picasa.Count) values" -ForegroundColor Gray
        write-host $ht_albums_picasa.Count -ForegroundColor Gray
        return $ht_albums_picasa
    }

    function GetAlbums_Picasa_return_json_object([string]$bearer_token, [int]$maxresults){
        write-host "GetAlbums_Picasa()" -ForegroundColor Gray
        
        ## Testing
        #$bearer_token = "ya29.Glz1Bb0D_2iXEsHnIlMoG86-8CLtWXiLRN7ByM_FSncbi1en_Nzd7R4tvs4De36oEr-L5b7TvRZ--qjM4shVIGuzQPajCncF_WxxYCDNkkxasYB7CKTQAmIKxA5MVw"
        #$maxresults = 0
        #

        $headers = @{"Authorization" = "Bearer $bearer_token"}
        $url = "https://picasaweb.google.com/data/feed/api/user/default?&kind=album"
        if($maxresults -ne 0){ $url += "&max-results=$maxresults"; }

        $ht_albums_picasa = @{}

        try {
            $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers

            $response | Where-Object $_.title
            $response[0]
            $response | where { $_.id -contains "1000000421995119" } | Select -ExpandProperty title
            
            $response | 
                Get-Random -Count 2 | 
                    foreach { [PSCustomObject]@{
                                                title=$_.title.'#text';
                                                numphotos=$_.numphotos;
                                                id=$_.id
                                               }
                            } | 
                        Format-List

            # title data is stored in the #text property, but if you don�t enclose "#text" in quotation marks, 
            # Windows PowerShell interprets it as a comment because it begins with a # sign, and you will receive an error message!

#key             = $key;
#src             = "Picasa";
#title           = $album.title.InnerText; 
#numphotos       = [int]$album.numphotos; 
#id              = $key;



            $i = 0

            foreach($album in $response){
                $ht_albums_picasa.Add($album.id.Split(" ")[1].ToString(), $album)
            }

            $results = foreach($album in $response){
                #Write-Host "$($album.id.Split(" ")[1])`t$($album.title.InnerText)`t$($album.numphotos.ToString())"
                #"$($album.id.Split(" ")[1])`t$($album.title.InnerText)`t$($album.numphotos.ToString())"

                $ht_albums_picasa.Add($album.id.Split(" ")[1].ToString(), $album)
                #$ht_albums_picasa.Add($album.id, $album)
            }
            $results | ft

        } catch {
            $script:ERR = $_
            Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ -ForegroundColor Red
            Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Red
        }


        #write-host "ht_albums_picasa contains: $($ht_albums_picasa.Count) values" -ForegroundColor Gray
        write-host $ht_albums_picasa.Count -ForegroundColor Gray
        return $ht_albums_picasa
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


#>