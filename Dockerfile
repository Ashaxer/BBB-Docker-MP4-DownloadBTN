FROM alangecker/bbb-docker-nginx:v3.0.4-v5.3.1-1.25

# Override playback index
COPY playback-index.html /www/playback/presentation/2.3/index.html
COPY mp4-downloads.nginx /etc/nginx/bbb/mp4-downloads.nginx
