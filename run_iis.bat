@REM| Launch Chrome and load localhost on port 8000 (defined within app.config <sites> element)
start "" "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" -url http://localhost:8000/

@REM| Configure HTTP.SYS at the kernel level to allow incoming connections from outside your computer
netsh http add urlacl url=http://*:8000/ user=Everyone

@REM| Configure the Windows firewall to allow incoming connections
@REM| https://technet.microsoft.com/en-us/library/dd734783(v=ws.10).aspx
@REM| Doing a delete (no harm if not exists) before create to avoid multiple entries with same name.
netsh advfirewall firewall delete rule name=IISExpressWeb protocol=tcp localport=8000
netsh advfirewall firewall add rule name=IISExpressWeb dir=in protocol=tcp localport=8000 profile=any remoteip=any action=allow

@REM| Start IIS Express using the specified application configuration file
start "" "%programfiles%\iis express\iisexpress" /config:"iis.config"














@REM| "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" -url http://localhost:8000/
@REM| Get the current working directory
@REM| set CURDIR=%CD%
@REM| start "" "%programfiles%\iis express\iisexpress" /config:"%CURDIR%\iis-app.config"
@REM| EXIT /B
@REM| "--allow-file-access-from-files"
@REM| ==============================================================================================
@REM| NOTES:
@REM| ==============================================================================================
@REM| http://www.iis.net/learn/extensions/using-iis-express/running-iis-express-from-the-command-line
@REM| 
@REM| RUNNING YOUR SITE FROM THE APPLICATION FOLDER:
@REM| iisexpress /path:app-path [/port:port-number] [/clr:clr-version] [/systray:boolean]
@REM| 
@REM| RUNNING YOUR SITE FROM A CONFIGURATION FILE
@REM| iisexpress [/config:config-file] [/site:site-name] [/siteid:site-id] [/systray:boolean]
@REM| ==============================================================================================
@REM| http://commandwindows.com/variables.htm