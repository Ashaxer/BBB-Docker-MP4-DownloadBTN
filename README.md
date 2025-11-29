# BBB-Docker-MP4-DownloadBTN
This module tries to screen record the published/unpublished recordings and add a beautiful download button for its web page. 

# How it works
When a recording is created inside published or unpublished folder, this service runs a docker container (manishkatyan/bbb-mp4) which creates a virtual chromium window and records the session using ffmpeg library. then copies the output video to the recording folder named after internal id which makes the video available to download directly. 
The rebuilt docker container of alangecker/bbb-docker-nginx:v3.0.4-v5.3.1-1.25 process, replaces the default playback.html file that makes it check for available recorded video and adds a download button if it found one.

