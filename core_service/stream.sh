#!/bin/sh
#
# IPカメラの映像をHLS形式で録画するffmpegラップスクリプト。
# 認証情報は環境変数から読み込む:
#   IPCAM_HOST  - カメラのIPアドレス:port
#   IPCAM_USER  - カメラのユーザー名
#   IPCAM_PWD   - カメラのパスワード
#
# 起動:
#   IPCAM_HOST=192.168.1.10:80 IPCAM_USER=admin IPCAM_PWD=xxxxx sh stream.sh
#
# ffmpegのPIDは ${VIDEO_ROOT}/ffmpeg.pid に保存される。
# 再起動時は旧プロセスを安全に停止してから新規起動する。

VIDEO_ROOT=/var/www/stream_root/video
PID_FILE="${VIDEO_ROOT}/ffmpeg.pid"
LOG_FILE="${VIDEO_ROOT}/ffmpeg.log"

# --- 認証情報の環境変数チェック ---
: "${IPCAM_HOST:?IPCAM_HOST environment variable is required}"
: "${IPCAM_USER:?IPCAM_USER environment variable is required}"
: "${IPCAM_PWD:?IPCAM_PWD environment variable is required}"

# --- 旧プロセスの停止(PIDファイル方式) ---
if [ -f "${PID_FILE}" ]; then
    OLD_PID=$(cat "${PID_FILE}" 2>/dev/null)
    if [ -n "${OLD_PID}" ] && kill -0 "${OLD_PID}" 2>/dev/null; then
        kill "${OLD_PID}" 2>/dev/null
        sleep 2
        # 強制終了が必要ならSIGKILL
        if kill -0 "${OLD_PID}" 2>/dev/null; then
            kill -9 "${OLD_PID}" 2>/dev/null
            sleep 1
        fi
    fi
    rm -f "${PID_FILE}"
fi

cd "${VIDEO_ROOT}" || {
    echo "ERROR: cannot cd to ${VIDEO_ROOT}" >&2
    exit 1
}

INPUT_URL="http://${IPCAM_HOST}/videostream.asf?user=${IPCAM_USER}&pwd=${IPCAM_PWD}"
FONT_FILE=/usr/share/fonts/truetype/freefont/FreeSans.ttf

# ffmpegをバックグラウンドで起動し、ログをファイルへ出力
nohup /usr/bin/ffmpeg -hide_banner -nostdin -loglevel warning \
    -i "${INPUT_URL}" \
    -vf "drawtext=text='%{localtime\:%F %T}':fontfile=${FONT_FILE}:fontcolor=white@1:fontsize=24:x=12:y=12" \
    -c:v h264_omx \
    -f hls -hls_time 5 -hls_list_size 120 -strftime 1 -strftime_mkdir 1 \
    -hls_flags second_level_segment_index \
    -hls_segment_filename "%Y%m%d/%H/%M_%%03d.ts" \
    -movflags faststart \
    playlist.m3u8 \
    >>"${LOG_FILE}" 2>&1 &

FFMPEG_PID=$!
echo "${FFMPEG_PID}" > "${PID_FILE}"

# 終了時にPIDファイルを削除
trap 'rm -f "${PID_FILE}"' EXIT

# 起動確認: 数秒待ってffmpegが生存しているか確認
sleep 5
if kill -0 "${FFMPEG_PID}" 2>/dev/null; then
    echo "ffmpeg started (pid=${FFMPEG_PID}), logging to ${LOG_FILE}"
else
    echo "ERROR: ffmpeg failed to start. Last log lines:" >&2
    tail -n 20 "${LOG_FILE}" >&2
    rm -f "${PID_FILE}"
    exit 1
fi
