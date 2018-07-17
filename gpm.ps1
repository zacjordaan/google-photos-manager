# https://github.com/RamblingCookieMonster/Invoke-Parallel
. "$PSScriptRoot\Invoke-Parallel.ps1"


$settings_path = Join-Path (Split-Path $Profile) gpm.settings



$global:clientreq        = ConvertFrom-Json "{'redirect_uris' : [ 'https://accounts.google.com/o/oauth2/approval' ]}"
$global:authcode         = $null
$global:hash_media_items = @{}
#$global:refresh_token

# OAuthPS
$CLIENTID                = "127194997596-u2h1uqgu2d05ocgt6i59mpb72pcn5kii.apps.googleusercontent.com"
$CLIENTSECRET            = "hC2iktQD7reOAq4vhWAdPWHG"
$SCOPES                  = @("https://www.googleapis.com/auth/photoslibrary","https://picasaweb.google.com/data")
$ERR                     = $null
$ALBUMS_CSV              = "C:\Users\ueszjv\Desktop\albums.csv"
#$ALBUMS_CSV              = "C:\Users\zacjordaan\Desktop\albums.csv"
$photos_directory        = ""





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
    But access tokens are only good for 1 hour and then they expire so before that time you need to use the Refresh_token to get a new access token. 
    Also if you are going to want to access your users data again you should save the refresh_token some place that will enable you to always access their data.

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

    function GetAuthCode([string]$authurl){
        write-host "GetAuthCode()" -ForegroundColor Gray

        # windows form and browser dependencies
        Add-Type -AssemblyName System.Windows.Forms 
        Add-Type -AssemblyName System.Web

        # create form for embedded browser
        $form = New-Object Windows.Forms.Form
        $form.Text          = "GetAuthCode()"
        $form.Width         = 600
        $form.Height        = 800
        $form.StartPosition = "CenterScreen"
        
        #$icon = New-Object system.drawing.icon ("$PSScriptRoot\img\star.ico") #[system.drawing.icon]::ExtractAssociatedIcon($PSHOME + "\powershell.exe")
        #$form.Icon = $icon
    
        # add a web browser to form
        $browser        = New-Object Windows.Forms.WebBrowser
        $browser.Size   = $form.ClientSize
        $browser.Anchor = "Left,Top,Right,Bottom"
        $form.Controls.Add($browser)

        # init global variable for authorization code response
        $Global:g_redirect_uri = $null

        # add handler for the embedded browser's Navigating event
        <#
        $browser.add_Navigating({
            write-host "Navigating to: $($_.Url)" -ForegroundColor Cyan
            write-host "Url.Authority:"$_.Url.Authority -ForegroundColor Gray
            write-host "Url.AbsolutePath:"$_.Url.AbsolutePath -ForegroundColor Gray
        
            # detect when browser is about to fetch redirect_uri
            $uri = [uri] $global:clientreq.redirect_uris[0]
        
            if($_.Url.Authority -eq $uri.Authority -And $_.Url.AbsolutePath -eq $uri.AbsolutePath) {
                # collect authorization response in a global
                $Global:g_redirect_uri = $_.Url
                # cancel event and close browser window
                $form.DialogResult = "OK"
                $form.Close()
                $_.Cancel = $true
            }
        })
        #>

        # add handler for the embedded browser's Navigated event
        $browser.add_Navigated({
            write-host "add_Navigated event: $($_.Url)" -ForegroundColor Gray

            # check if browser fetched redirect_uri
            $uri = [uri] $global:clientreq.redirect_uris[0]

            if($_.Url.Authority -eq $uri.Authority -And $_.Url.AbsolutePath -eq $uri.AbsolutePath) {

                # parse authorization response and save it
                $Global:g_redirect_uri = $_.Url

                $document_title = $browser.DocumentTitle # e.g. Success code=4/AACxuRJGlREdpSxBIoCu9pTxpKb8QvuLNPafSTXondlG0JhvL6v73Fk
                $qs = $document_title.Split("=");

                if($qs[0] -eq "Success code"){
                    $global:authcode = $qs[1];

                    # close browser window
                    $form.DialogResult = "OK"
                    $form.Close()
                }
            }
        })


        # send authorization code request
        $browser.Navigate($authurl)

        # show browser window, wait for window to close
        if($form.ShowDialog() -ne "OK") {
            write-host "WebBrowser: Canceled" -ForegroundColor Gray
            return $null
        }

        return $global:authcode;
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
        write-host "RefreshAccessToken()" -ForegroundColor Gray

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

    function CheckToken([string]$access_token){
        
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

        <# Testing
        $access_token = "ya29.Glv3BamWghjT6twpxzGR7IKD3GDiVa2JDzwYw-GL93h5Gp3QIraRiLprn3Lna2zfdgaAq6t25u_dT3nLWTycJt_P9vya68d77Pc4Xe22RqpQEF9B9rnagKol1SDJ"
        #$access_token = $null
        #>
        
        try {
            $url = "https://www.googleapis.com/oauth2/v3/tokeninfo?access_token=$access_token"
            $obj_token_info = Invoke-RestMethod $url

            if(!$obj_token_info){
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
        } catch {
            $script:ERR = $_
            Write-Host "`tStatusCode:" $_.Exception.Response.StatusCode.value__ -ForegroundColor Gray
            Write-Host "`tStatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Gray
        }

    }
    
    function Check-Token([string]$access_token){
    #WIP
        
        write-host "CheckToken()" -ForegroundColor Gray

        if($global:refresh_token -eq $null){
            # Get refresh token if previously saved
            write-host "Loading refresh_token from disk" -ForegroundColor Gray
            $cred_path = Join-Path (Split-Path $Profile) gpm_refresh_token.credential
            if(Test-Path $cred_path -PathType Leaf){ $global:refresh_token = Import-CliXml $cred_path }
        }

        write-host $("global:refresh_token = $global:refresh_token") -ForegroundColor Gray

        <# Testing
        cls
        $url            = $null
        $obj_token_info = $null
        $access_token   = $null
        #$access_token   = "ya29.Glv3BamWghjT6twpxzGR7IKD3GDiVa2JDzwYw-GL93h5Gp3QIraRiLprn3Lna2zfdgaAq6t25u_dT3nLWTycJt_P9vya68d77Pc4Xe22RqpQEF9B9rnagKol1SDJ"
        #>

        <#
        $private:return = @{"status"=0}
        $uri = "https://www.googleapis.com/oauth2/v3/tokeninfo?access_token=$access_token"

        # create http headers for use in rest call
        #$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        #$headers.Add("Authorization", "123456")

        # attempt rest call, catch errors
        try {
	        $obj_token_info = Invoke-RestMethod -uri $uri
        }
        catch {
	        $msg = 
	        Write-host "Failed to get tokeninfo" -ForegroundColor Gray
	        $Private:return.exception = $_.Exception
	        $Private:return.status = -1
        }

        # get HTTP status description
        $Private:return.exception.response.statusdescription

        # get http status code as string
        $Private:return.exception.response.statuscode
        
        # get http status code as numerical value
        [int]$Private:return.exception.response.statuscode

        # set status code to var
        $statuscode = [int]$Private:return.exception.response.statuscode

        #https://www.restapitutorial.com/httpstatuscodes.html
        if ($statuscode -eq 400) {
            # bad data?
            $dosomethingelse
        }
        if ($statuscode -eq 401) {
            # failed to auth
            $dosomthing
        }
        if ($Private:return.status -eq -1) {
            #catch any other exceptions
            $dosomethingdifferent
        }
        else {
            # IT WORKED continue on
            $moveon
        }


        try {
            $url = "https://www.googleapis.com/oauth2/v3/tokeninfo?access_token=$access_token"
            $obj_token_info = Invoke-RestMethod $url

            if(!$obj_token_info){
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
        } catch {
            $script:ERR = $_
            Write-Host "`tStatusCode:" $_.Exception.Response.StatusCode.value__ -ForegroundColor Gray
            Write-Host "`tStatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Gray
        }

        #>
    }




# -----------------------------------------------------------------------------
#endregion

#region API FUNCTIONS
# -----------------------------------------------------------------------------

    function Get-Albums([string]$access_token){
        write-host "Get-Albums()" -ForegroundColor Gray

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
            $progressPreference = 'silentlyContinue'    # Subsequent calls should not display UI
            $dt_start = Get-Date
            while($nextPageToken -ne $null){
                if($nextPageToken -ne $null){ $thisurl = $url + "&pageToken=$nextPageToken"; }
                $response      = Invoke-RestMethod -Uri $thisurl -Method Get -Headers $headers
                $nextPageToken = $response.nextPageToken
                $google_albums += $response.albums
            }
            $dt_end = Get-Date
            $elapsed_time = ($dt_end - $dt_start)
            Write-Host $("`t...{0:hh\:mm\:ss}" -f $elapsed_time) -ForegroundColor Gray
            $progressPreference = 'Continue'            # Subsequent calls will display UI
        } catch {
            $script:ERR = $_
            Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ -ForegroundColor Red
            Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Red
        }

        return $google_albums

        #https://developers.google.com/photos/library/guides/performance-tips
        #https://www.googleapis.com/demo/v1?key=YOUR-API-KEY&fields=kind,items(title,characteristics/length)
    }

    function Get-MediaItems([string]$access_token, [string]$album_id){
        write-host -NoNewline "Get-MediaItems()" -ForegroundColor Gray

        # https://developers.google.com/photos/library/guides/list#listing-library-contents

        <# Testing
        $access_token = "ya29.Glv3BRBzfNU3qgCX34tSgnNxqGpWYfZh8vHttj8tIU2MIyq7f_Zti82pQBWBS2AlBtAbVeGBiB51GTMDCYAUca8YelYF7zJ9zdvoXQ82xQeslgALdL7wJCO8pCnI"
        $album_id     = "AGj1epVPjGrcUZB_qcbUfzIoKaJIOryIaX6V2xbDzyofiOLoRIW2"        # Zac & Melanie's Engagement (20)
        #>

        $i             = 0
        $nextPageToken = ""
        $headers       = @{"Authorization" = "Bearer $access_token";} 

        try {

            while($nextPageToken -ne $null -And $i -lt 5){ # <-- SAFETY LIMIT VARIABLE i HERE
                $i++

                $url = "https://photoslibrary.googleapis.com/v1/mediaItems:search?pageSize=500" #default: 100, max: 500

                if($album_id -ne $null){ $url += "&albumId=$album_id" }
                if($nextPageToken -ne ""){ $url += "&pageToken=$nextPageToken" }

                # execute POST request
                $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers
                
                # check pagination
                $nextPageToken = $response.nextPageToken
        
                $mediaItems = $response.mediaItems 


                # Print results to console (selected properties only)
                #$mediaItems | Select-Object id, description, mimeType | Format-Table -auto
                #@{N="MediaTypeP";E={$_.mediaMetadata.photo}},
                #https://stackoverflow.com/questions/29595518/is-the-following-possible-in-powershell-select-object-property-subproperty 
          

                # Append (export) results to csv (selected properties only)
                #$albums | Select-Object id, title, totalMediaItems, productUrl | export-csv -NoTypeInformation -append -path $ALBUMS_CSV_ALBUMS
            }

        } catch {
            $script:ERR = $_
            Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ -ForegroundColor Red
            Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Red
        }

        write-host "`t$($mediaItems.count)" -ForegroundColor Gray
        return $mediaItems
    }

    function Get-Filename([string]$access_token, [string]$base_url){
        #write-host "Get-Filename('$($access_token.substring(0,3))...', '$($base_url.substring(0,4))...')" -ForegroundColor Gray

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
            
            $progressPreference = 'silentlyContinue'    # Subsequent calls do not display UI.
            $media_item = Invoke-WebRequest -Uri $url -Method Get #-Headers $headers
            $progressPreference = 'Continue'            # Subsequent calls do display UI.

            $filename   = ([System.Net.Mime.ContentDisposition]$media_item.Headers.'Content-Disposition').FileName

        } catch {
            $script:ERR = $_
            Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ -ForegroundColor Red
            Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Red
        }

        return $filename
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

# -----------------------------------------------------------------------------
#endregion

function Select-Folder {

    Add-Type -AssemblyName System.Windows.Forms
    $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog

    #$FolderBrowser.SelectedPath = "C:\"
    if($photos_directory){ $FolderBrowser.SelectedPath = $photos_directory; }
    else{ $FolderBrowser.SelectedPath = [environment]::getfolderpath("MyPictures") }
    #else{ $FolderBrowser.RootFolder = "MyPictures" }

    $FolderBrowser.ShowNewFolderButton = $false
    $FolderBrowser.Description = "Select a directory"

    $loop = $true
    while($loop){
        if ($FolderBrowser.ShowDialog() -eq "OK"){
            $loop = $false
        }else{
            return
        }
    }
    $path = $FolderBrowser.SelectedPath
    $FolderBrowser.Dispose()
    return $path
} 
 


#################################################################
# INIT
# Remove-Variable settings;
# Remove-Item -Path $settings_path
#################################################################

# Clear screen
Clear-Host

if($settings -eq $null)
{
    if(Test-Path $settings_path -PathType Leaf){
        write-host "Reading Settings"
        $settings = Import-CliXml $settings_path 
    }
    else
    {
        # Initialize settings
        $settings = @{
                    "client_id"     = "127194997596-u2h1uqgu2d05ocgt6i59mpb72pcn5kii.apps.googleusercontent.com";
                    "scopes"        = @("https://www.googleapis.com/auth/photoslibrary","https://picasaweb.google.com/data")
                    }
        $defaultValue = 'hC2iktQD7reOAq4vhWAdPWHG'
        $settings.client_secret = if (($result = Read-Host "Press enter to accept default value $defaultValue") -eq '') {$defaultValue} else {$result}

        # Save them for later
        $settings | Export-CliXml $settings_path
    }
} 


if(!$settings.photos_directory){ 
    $settings.photos_directory = Select-Folder 
    $settings | Export-CliXml $settings_path
}
#$settings

#######################################
return
#######################################



#################################################################
# MAIN
#################################################################


# Get refresh token if previously saved
#$cred_path = Join-Path (Split-Path $Profile) gpm_refresh_token.credential
#if(Test-Path $cred_path -PathType Leaf){ $REFRESH_TOKEN = Import-CliXml $cred_path }
#Get-Variable bla* | Export-Clixml vars.xml
#Import-Clixml .\vars.xml | %{ Set-Variable $_.Name $_.Value }

#region OAUTH
#------------------------------------------------------------------------------

#$ACCESS_TOKEN = $null
#$REFRESH_TOKEN = $null
if($ACCESS_TOKEN -eq $null -and $REFRESH_TOKEN -eq $null){
    
    Write-Host "OAuthorization required" -ForegroundColor Yellow

    # Ask for access (Get OAuth2 Authorization Code)
    $url = "https://accounts.google.com/o/oauth2/auth?client_id=$CLIENTID&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=$($SCOPES -Join " ")&response_type=code";
    $authcode = GetAuthCode $url

    write-host "AuthCode: $authcode" -ForegroundColor Yellow

    # Exchange Authentication Code for AccessToken
    write-host "Exchanging AuthCode Code for AccessToken..." -ForegroundColor yellow
    $token         = ExchangeCode $CLIENTID $CLIENTSECRET $authcode
    $ACCESS_TOKEN  = $token.access_token
    $REFRESH_TOKEN = $token.refresh_token

    # save refresh_token to disk
    $CredXmlPath = Join-Path (Split-Path $Profile) gpm_refresh_token.credential
    $REFRESH_TOKEN | Export-CliXml $CredXmlPath
}
elseif($ACCESS_TOKEN -eq $null -and $REFRESH_TOKEN -ne $null){
    Write-Host "No access_token but we do have a refresh_token..." -ForegroundColor Yellow

    # Refresh Access Token
    $ACCESS_TOKEN = RefreshAccessToken $CLIENTID $CLIENTSECRET $REFRESH_TOKEN
}

# Check that access token is valid and refresh if necessary

$obj_token_info = CheckToken $ACCESS_TOKEN
if(!$obj_token_info -And $REFRESH_TOKEN -ne $null){ 
    write-host "No token info available... may have already expired. Refresh and try again"
    $ACCESS_TOKEN = RefreshAccessToken $CLIENTID $CLIENTSECRET $REFRESH_TOKEN 
    $obj_token_info = CheckToken $ACCESS_TOKEN
} 

if($obj_token_info){
    $ts = [timespan]::fromseconds($obj_token_info.expires_in)
    $dt_expiry = (Get-Date) + $ts
    write-host $("Access Token OK... expires in {0:hh\:mm\:ss} at {1:hh\:mm\:ss}" -f $ts, $dt_expiry) -ForegroundColor Green
    if($ts.Minutes -lt 10){ $ACCESS_TOKEN = RefreshAccessToken $CLIENTID $CLIENTSECRET $REFRESH_TOKEN; }
}
else{
    write-host "Access Token could not be verified!" -ForegroundColor Red
    return
}


#$m = [timespan]::($dt_expiry-(Get-Date))
#
#$m.Minute
#
#if(   -lt 5  ){
#
#}
#
#$StartDate=(GET-DATE)
#
#$EndDate=[datetime]”01/01/2014 00:00”
#
#NEW-TIMESPAN –Start $StartDate –End $EndDate
#
#$obj_token_info = CheckToken $ACCESS_TOKEN

###################
#return
###################


#------------------------------------------------------------------------------
#endregion


#20060000 - Misc
#Get-MediaItems $access_token "AGj1epUkkuYXE15k637KamAHbEuSp02gNc0aRo9rogogznU13OKt";


#$albums = $null;
if($albums -eq $null){ 

    #$albums = Get-Albums $access_token 

    #<#
    if (Test-Path $ALBUMS_CSV) {
        # albums.csv exists - prompt to load from file instead of calling Google Photos API
        $confirmation = Read-Host "Album data found at ""$ALBUMS_CSV""`nLoad albums from file instead of Google Photos API?"
        if ($confirmation -eq "y" -or $confirmation -eq "yes") {

            $cols = "album_idx", "title", "totalMediaItems", "album_id"

            $albums = Import-Csv $ALBUMS_CSV | 
                #Select-Object $cols -First 780 |
                    Group-Object $cols |
                        Select-Object @{n = 'album_idx';       e = {$_.Group[0].album_idx}},
                                      @{n = 'title';           e = {$_.Group[0].title}}, 
                                      @{n = 'totalMediaItems'; e = {$_.Group[0].totalMediaItems}}, 
                                      @{n = 'album_id';        e = {$_.Group[0].album_id}}, 
                                      @{n = 'count_items';     e = {$_.Count}}

            #$albums | Where-Object { $_.totalMediaItems -ne $_.count_items } | Format-Table -AutoSize

        } else{
            $albums = Get-Albums $access_token 
        }
    } else {
        $albums = Get-Albums $access_token 
    }
    #>
}


write-host "Google albums: $($albums.Count)"
write-host
#return


$parsed_albums = $albums | 
    #Get-Random -Count 3 <#| 
        Sort-Object -Property @{Expression={$_.title}} -Descending |
            Foreach-Object {$i=1}{$_ | Add-Member "album_idx" ($i++) -Force -PassThru} |
                Select-Object -Property album_idx, title, totalMediaItems, @{N='album_id';E={$_.id}} |
                    Where-Object {$_.totalMediaItems -ne $null} |
                        Select -First 5
                        #Where-Object {$_.title -in "promo2","PROMO" }

#$parsed_albums | Format-List
#where-object { $_.album_idx -gt 117 }
#Where-Object {$_.title -in "20170513 Kata-Kanu","20170513 JOTT","20170512 Jem Loses His First Tooth" -And $_.totalMediaItems -ne $null } |

#Get-MediaItems $access_token "AGj1epUDOQUGd0ZMKCsri7V3zL4WIizTzM3OuL6iocPAiGjLHO0q"
#Get-MediaItems $access_token "AGj1epW_xJ0ASfeQP9SO2ir0G45dLEHWue6iDangQA25fw8FNgZH"

###################
#return
###################



$dt_start = Get-Date
ForEach($album in $parsed_albums){
    
    Write-Host "$($album.album_idx)`t$(Get-Date)`t$($album.title) ($($album.totalMediaItems))"

    $media_items = Get-MediaItems $access_token $album.album_id |
        ForEach-Object{$i=1;}{[PSCustomObject] @{
                                                album_idx       = $album.album_idx
                                                title           = $album.title
                                                totalMediaItems = $album.totalMediaItems
                                                album_id        = $album.album_id
                                                item_idx        = $i;
                                                mimeType        = $_.mimeType;
                                                mediaItemId     = $_.id;
                                                baseUrl         = $_.baseUrl;
                                                };
                                                #fileName        = Get-Filename $access_token $_.baseUrl;
                            $i++ 
                        }
        
    
    $media_items | 
    Invoke-Parallel -ImportVariables -ImportFunctions -ScriptBlock {
        $updated_media_item = $_ | 
            Add-Member "fileName" (Get-Filename $access_token $_.baseUrl) -Force -PassThru |
                Select-Object album_idx,title,totalMediaItems,album_id,item_idx,fileName,mimeType,mediaItemId;
        $album_mediaItem_key = "$($updated_media_item.album_id)|$($updated_media_item.mediaItemId)"
        $global:hash_media_items.Add($album_mediaItem_key, $updated_media_item);
    }

}

$dt_end = Get-Date
$elapsed_time = ($dt_end - $dt_start)
Write-Host $("`nProcessed $($global:hash_media_items.Count) album filenames in: {0:hh\:mm\:ss}" -f $elapsed_time) -ForegroundColor Cyan


$confirmation = "y"
if(Test-Path -Path $ALBUMS_CSV -PathType leaf){ $confirmation = Read-Host """$ALBUMS_CSV"" already exists. Overwrite it?" }

if ($confirmation -eq "y" -or $confirmation -eq "yes") {
    $global:hash_media_items.Values | 
        Export-Csv -Path $ALBUMS_CSV -NoTypeInformation
        
    Write-Host "Exported to $ALBUMS_CSV" -ForegroundColor Cyan
} else{
    write-host "Export-Csv cancelled."
}



#Write-Host "Albums exported to $ALBUMS_CSV" -ForegroundColor Yellow
write-host "`nFIN" -ForegroundColor Yellow














<# Original - Serial
$a = 0
$dt_start = Get-Date
$album_start_time = Get-Date

foreach($album in $parsed_albums){
#foreach($album in $parsed_albums | where { $_.album_idx -gt 394 }){
#foreach($album in $parsed_albums | where { $_.title -eq "20180403 Toby's 5th Birthday" }){

    Write-Host "$($album.album_idx)`t$(Get-Date)`t$($album.title) ($($album.totalMediaItems))"
    $media_items = Get-MediaItems $access_token $album.album_id;

    $a++
    $album_seconds_elapsed = ((Get-Date) - $album_start_time).TotalSeconds
    $album_seconds_remaining = ($album_seconds_elapsed / ($a / ($parsed_albums.Count))) - $album_seconds_elapsed
    $album_percent_complete = $($a-1)/$($parsed_albums.Count)
    Write-Progress -Id 1 `
                   -Activity "Album $($a) of $($parsed_albums.Count)" `
                   -Status "Progress: " `
                   -CurrentOperation "$("{0:p0}" -f $album_percent_complete)" `
                   -PercentComplete $album_percent_complete;
                   #-SecondsRemaining $album_seconds_remaining `

    $start_time = Get-Date


    $parsed_media_items = 
        $media_items | 
            #Get-Random -Count 3 | 
            ForEach-Object{
                            $i=1;
                          }{

                            $seconds_elapsed = ((Get-Date) - $start_time).TotalSeconds
                            $seconds_remaining = ($seconds_elapsed / ($i / ($album.totalMediaItems))) - $seconds_elapsed
                            $item_percent_complete = $($i-1)/$($album.totalMediaItems)*100
                            Write-Progress -ParentId 1 `
                                           -Activity "Downloading Filename $($i) of $($album.totalMediaItems)" `
                                           -Status "$($album.title): " `
                                           -CurrentOperation "$("{0:N1}" -f $item_percent_complete,2)% complete" `
                                           -SecondsRemaining $seconds_remaining `
                                           -PercentComplete $item_percent_complete;

                                [PSCustomObject] @{
                                                  album_idx       = $album.album_idx
                                                  title           = $album.title
                                                  totalMediaItems = $album.totalMediaItems
                                                  album_id        = $album.album_id
                                                  item_idx        = $i;
                                                  fileName        = Get-Filename $access_token $_.baseUrl;
                                                  mimeType        = $_.mimeType;
                                                  mediaItemId     = $_.id;
                                                  };
                                $i++ 
                              } | 
                Sort-Object -Property fileName

    foreach($updated_media_item in $parsed_media_items){
        $global:hash_media_items.Add($updated_media_item.mediaItemId, $updated_media_item);
    }
    
    #$parsed_media_items | Export-Csv -NoTypeInformation -append -path $ALBUMS_CSV
    
}

$dt_end = Get-Date
$elapsed_time = ($dt_end - $dt_start)
Write-Host $("`nProcessed $($global:hash_media_items.Count) album filenames in: {0:hh\:mm\:ss}" -f $elapsed_time) -ForegroundColor Cyan
#>
