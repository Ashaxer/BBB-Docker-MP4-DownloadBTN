# BBB-Docker-MP4-DownloadBTN
This module tries to screen record the published/unpublished recordings and add a beautiful download button for its web page. 
Special thanks to [manishkatyan](https://github.com/manishkatyan/bbb-mp4) for his work!

# How it works
When a recording is created inside published or unpublished folder, this service runs a docker container (manishkatyan/bbb-mp4) which creates a virtual chromium window and records the session using ffmpeg library. then copies the output video to the recording folder named after internal id which makes the video available to download directly. 
The rebuilt docker container of alangecker/bbb-docker-nginx:v3.0.4-v5.3.1-1.25 process, replaces the default playback.html file that makes it check for available recorded video and adds a download button if it found one.

# Setup

Step 1: Clone using git:
```
git clone https://github.com/Ashaxer/BBB-Docker-MP4-DownloadBTN.git
cd BBB-Docker-MP4-DownloadBTN
```

Step 2: Configure your values inside example.env file:
```
nano example.env
```

Step 3: Install the recorder container script:
```
sudo bash install.sh
```

Step 4: Build the new container: 

*Before applyhing any changes to your container, make sure what you are doing, I replaced my container and "it works on my machine". feel free to create issues*
If you want to create a new container:
```
docker build -t bbb-docker-nginx:custom .
```

If you want to replace your current container:
```
docker build -t alangecker/bbb-docker-nginx:v3.0.4-v5.3.1-1.25 .
```

To run the new container, go to root of your bbb directory and run this:
```
docker compose up -d
```
