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
# ffmpegのPIDとログは ${IPCAM_STATE_DIR} (既定: ~/.local/state/ipcam-recorder) に保存される。
# ログにはカメラの認証情報を含むURLが出力され得るため、Webから配信される
# ${VIDEO_ROOT} 配下には置かない。
# 再起動時は旧プロセスを安全に停止してから新規起動する。

VIDEO_ROOT=/var/www/stream_root/video
STATE_DIR="${IPCAM_STATE_DIR:-${HOME}/.local/state/ipcam-recorder}"
PID_FILE="${STATE_DIR}/ffmpeg.pid"
LOG_FILE="${STATE_DIR}/ffmpeg.log"

# --- 認証情報の環境変数チェック ---
: "${IPCAM_HOST:?IPCAM_HOST environment variable is required}"
: "${IPCAM_USER:?IPCAM_USER environment variable is required}"
: "${IPCAM_PWD:?IPCAM_PWD environment variable is required}"

# --- 状態ディレクトリ(PID・ログ)の準備: 所有者のみアクセス可 ---
mkdir -p "${STATE_DIR}" && chmod 700 "${STATE_DIR}" || {
    echo "ERROR: cannot prepare ${STATE_DIR}" >&2
    exit 1
}

# PIDが実際にffmpegか確認する(再起動後のPID使い回しで無関係なプロセスを止めないため)
is_ffmpeg() {
    [ -r "/proc/$1/cmdline" ] && tr '\0' ' ' < "/proc/$1/cmdline" | grep -q 'ffmpeg'
}

# --- 旧プロセスの停止(PIDファイル方式) ---
if [ -f "${PID_FILE}" ]; then
    OLD_PID=$(cat "${PID_FILE}" 2>/dev/null)
    if [ -n "${OLD_PID}" ] && kill -0 "${OLD_PID}" 2>/dev/null && is_ffmpeg "${OLD_PID}"; then
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
VIDEO_FILTER="drawtext=text='%{localtime\:%F %T}':fontfile=${FONT_FILE}:fontcolor=white@1:fontsize=24:x=12:y=12"

# ffmpegをバックグラウンドで起動し、ログをファイルへ出力
nohup /usr/bin/ffmpeg -hide_banner -nostdin -loglevel warning \
    -i "${INPUT_URL}" \
    -fps_mode passthrough \
    -vf "${VIDEO_FILTER}" \
    -c:v libx264 \
    -g 125 \
    -c:a aac \
    -b:a 24k \
    -ar 8000 \
    -ac 1 \
    -f hls -hls_time 5 -hls_list_size 120 -strftime 1 -strftime_mkdir 1 \
    -hls_flags second_level_segment_index+independent_segments \
    -hls_segment_filename "%Y%m%d/%H/%M_%%03d.ts" \
    -movflags faststart \
    playlist.m3u8 \
    >>"${LOG_FILE}" 2>&1 &

FFMPEG_PID=$!
echo "${FFMPEG_PID}" > "${PID_FILE}"

# 注意: このスクリプトは起動確認後に終了するが、ffmpegは動き続ける。
# そのためEXIT trapでPIDファイルを消してはいけない(次回起動時に旧プロセスを止められなくなる)。

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
