@REM| If installed, use Python as a simple HTTP server for a quick way to host static content.
@REM| Change dir to folder with static content and type python -m SimpleHTTPServer 8000; everything in the directory will be available at http:/localhost:8000/
D:
cd "D:\Libraries\Documents\Projects\google-photos-manager"
py -m http.server 8000