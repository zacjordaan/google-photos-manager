﻿# https://github.com/globalsign/OAuth-2.0-client-examples/blob/master/PowerShell/Powershell-example.ps1
# Also: https://stackoverflow.com/questions/45446268/using-powershell-to-get-oauth2-authorization-code-for-google-sheets

# configuration

# enable verbose output
$VerbosePreference = "Continue"

# client registration request json, upload to sso
$Global:clientreq = ConvertFrom-Json @"
{
"redirect_uris" : [ "https://client1.ubidemo.com" ]
}
"@
# client registration response json, download from sso
$clientres = ConvertFrom-Json @"
{
"client_id" : "client1",
"client_secret" : "client1.secret"
}
"@
# resource server registration response json, download from sso
$resource = ConvertFrom-Json @"
{
"client_id" : "resource1",
"client_secret" : "resource1.secret"
}
"@
# authorization server metadata
$metadata = Invoke-RestMethod -Uri "https://login.test.globalsignid.com/uas/oauth2/metadata.json"
Write-Verbose "metadata.json: $($metadata)"

# windows forms dependencies
Add-Type -AssemblyName System.Windows.Forms 
Add-Type -AssemblyName System.Web

# create window for embedded browser
$form = New-Object Windows.Forms.Form
$form.Width = 640
$form.Height = 480
$web = New-Object Windows.Forms.WebBrowser
$web.Size = $form.ClientSize
$web.Anchor = "Left,Top,Right,Bottom"
$form.Controls.Add($web)
# global for collecting authorization code response
$Global:redirect_uri = $null
# add handler for the embedded browser's Navigating event
$web.add_Navigating({
    Write-Verbose "Navigating $($_.Url)"
    # detect when browser is about to fetch redirect_uri
    $uri = [uri] $Global:clientreq.redirect_uris[0]
    if($_.Url.Authority -eq $uri.Authority) {
        # collect authorization response in a global
        $Global:redirect_uri = $_.Url
        # cancel event and close browser window
        $form.DialogResult = "OK"
        $form.Close()
        $_.Cancel = $true
    }
})

# send authorization code request, scope either userinfo or client_id of resource server
$scope = "openid"
#$scope = $resource.client_id
$web.Navigate("$($metadata.authorization_endpoint)?scope=$($scope)&response_type=code&redirect_uri=$($clientreq.redirect_uris[0])&client_id=$($clientres.client_id)")
# show browser window, waits for window to close
if($form.ShowDialog() -ne "OK") {
    Write-Verbose "WebBrowser: Canceled"
    return
}
if(-not $Global:redirect_uri) {
    Write-Verbose "WebBrowser: redirect_uri is null"
    return
}

# decode query string of authorization code response
$response = [Web.HttpUtility]::ParseQueryString($Global:redirect_uri.Query)
if(-not $response.Get("code")) {
    Write-Verbose "WebBrowser: authorization code is null"
    return
}
# http basic authorization header for token request
$basic = @{ "Authorization" = ("Basic", [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(($clientres.client_id, $clientres.client_secret -join ":"))) -join " ") }
# send token request
$tokenrequest = @{ "grant_type" = "authorization_code"; "redirect_uri" = $clientreq.redirect_uris[0]; "code" = $response.Get("code") }
Write-Verbose "token-request: $([pscustomobject]$tokenrequest)"
$token = Invoke-RestMethod -Method Post -Uri $metadata.token_endpoint -Headers $basic -Body $tokenrequest
Write-Verbose "token-response: $($token)"

if($token.scope -eq "openid") {
    # userinfo request
    $bearer = @{ "Authorization" = ("Bearer", $token.access_token -join " ") }
    Invoke-RestMethod -Uri $metadata.userinfo_endpoint -Headers $bearer
} elseif($token.scope -eq "resource1") {
    # tokeninfo request
    $basic = @{ "Authorization" = ("Basic", [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(($resource.client_id, $resource.client_secret -join ":"))) -join " ") }
    $tokeninfo = @{ "token" = $token.access_token }
    Write-Verbose "tokeninfo-request: $([pscustomobject]$tokeninfo)"
    Invoke-RestMethod -Method Post -Uri $metadata.tokeninfo_endpoint -Headers $basic -Body $tokeninfo
}