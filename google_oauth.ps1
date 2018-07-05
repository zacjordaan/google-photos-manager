#  Setup:
#
#  Step 1: create new project on https://console.developers.google.com.
#  Step 2: Create oauth credentials type native or other.
#          Save the client id and secret. 
#  Step 3: Enable the api you are intersted in accessing.
#          Look up what scopes you need for accssing this api,
#  Step 4: Using the client id, and client secret...
#
#
# Inital Authenticate:  Authentication must be done the first time via a webpage to create the link you will need.  More then one scope can be added simply by seporating them with a comama
#     Place it in a webbrowser. 
#
#    https://accounts.google.com/o/oauth2/auth?client_id={CLIENT ID}&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope={SCOPES}&response_type=code
#
#    Copy the authencation code and run the following script.  
#      note: AuthorizationCode can only be used once you will need to save the refresh token returned to you.  


$clientId = "{CLIENT ID}";
$secret = "{SECRET}";
$redirectURI = "urn:ietf:wg:oauth:2.0:oob";
$AuthorizationCode = '{Code from web browser link above}'; 

$tokenParams = @{
	  client_id=$clientId;
  	  client_secret=$secret;
          code=$AuthorizationCode;
	  grant_type='authorization_code';
	  redirect_uri=$redirectURI
	}

$token = Invoke-WebRequest -Uri "https://accounts.google.com/o/oauth2/token" -Method POST -Body $tokenParams | ConvertFrom-Json

# Save this
$token.refresh_token  


##########################################################################################################################
#
# Using refresh token to get new access token
# The access token is used to access an api by sending the access_token parm with any request. 
#  Access tokens are only valid for about an hour after that you will need to request a new one using your refresh_token
#
##########################################################################################################################

$clientId = "{CLIENT ID}";
$secret = "{SECRET}";
$redirectURI = "urn:ietf:wg:oauth:2.0:oob";
$refreshToken = "{Refresh token from the authentcation flow}";

$refreshTokenParams = @{
	  client_id=$clientId;
  	  client_secret=$secret;
          refresh_token=$refreshToken;
	  grant_type='refresh_token';
	}

$refreshedToken = Invoke-WebRequest -Uri "https://accounts.google.com/o/oauth2/token" -Method POST -Body $refreshTokenParams | ConvertFrom-Json

$accesstoken = $refreshedToken.access_token

# This will work assuming you used the gmail scope I was just testing this
$messages = Invoke-WebRequest -Uri "https://www.googleapis.com/gmail/v1/users/me/messages?access_token=$accesstoken"-Method Get | ConvertFrom-Json

# Apperntly powershell 2.0 doesnt have Invoke-WebRequest we can also use Invoke-RestMethod
#
Invoke-RestMethod -Uri  "https://www.googleapis.com/gmail/v1/users/me/messages?access_token=$accesstoken" | select-object -expandproperty messages | format-table
