#!/bin/sh

pid=`ps -ea | grep ff[m]peg | awk '{print $1}'`
if [ -n "${pid}" ]; then
    kill ${pid}
fi

VIDEO_ROOT=/var/www/stream_root/video
cd ${VIDEO_ROOT}
rm -r ${VIDEO_ROOT}/*

HOST=[your IPCamera ip address:port]
USER_ID=[your IPCamera user id]
USER_PWD=[your IPCamera user password]
INPUT_URL="http://${HOST}/videostream.asf?user=${USER_ID}&pwd=${USER_PWD}"
FONT_FILE=/usr/share/fonts/truetype/freefont/FreeSans.ttf

/usr/bin/ffmpeg -hide_banner -nostdin -loglevel fatal \
-i ${INPUT_URL} -vf "drawtext=text='%{localtime\:%F %T}':fontfile=${FONT_FILE}:fontcolor=white@1:fontsize=24:x=12:y=12" -c:v h264_omx \
-f hls -hls_time 5 -hls_list_size 120 -strftime 1 -strftime_mkdir 1 -hls_flags second_level_segment_index -hls_segment_filename "%Y%m%d/%H/%M_%%03d.ts" -movflags faststart \
playlist.m3u8 &
