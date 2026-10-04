'use strict';

(function () {

	function playHLS(id, name) {
		var video = document.getElementById(id);
		if (video.canPlayType('application/vnd.apple.mpegurl')) {
			video.src = name;
			video.addEventListener('loadedmetadata', function () { video.play(); });
		} else if (Hls.isSupported()) {
			var hls = new Hls();
			hls.loadSource(name);
			hls.attachMedia(video);
			hls.on(Hls.Events.MANIFEST_PARSED, function () { video.play(); });
		}
	}

	function playRecord() {
		playHLS('video', this.getAttribute('data-src'));
	}

	function buildRecord(json) {
		var list = document.getElementById('record');
		list.textContent = '';
		json = json.sort(function (a, b) { return b.date - a.date; });
		for (var d = 0; d < json.length; ++d) {
			var dt = document.createElement('dt');
			var date_s = '' + json[d].date;
			var Y = date_s.substr(0, 4);
			var M = date_s.substr(4, 2);
			var D = date_s.substr(6);
			dt.textContent = Y + '-' + M + '-' + D;
			list.appendChild(dt);
			var dd = document.createElement('dd');
			var hours = json[d].hours.sort(function (a, b) { return b.hour - a.hour; });
			for (var h = 0; h < hours.length; ++h) {
				var box = document.createElement('div');
				var thumbnail = document.createElement('img');
				thumbnail.className = 'thumbnail';
				thumbnail.src = 'video/' + hours[h].thumb;
				thumbnail.setAttribute('data-src', 'video/' + hours[h].path);
				thumbnail.onclick = playRecord;
				box.appendChild(thumbnail);
				var title = document.createElement('span');
				title.className = 'title';
				title.textContent = hours[h].hour + ':00';
				box.appendChild(title);
				dd.appendChild(box);
			}
			list.appendChild(dd);
		}
	}

	// --- 稼働状況(status.json)の表示 ---
	// status.pl が毎分書き出す status.json を、1分間隔のポーリングで取得して表示する。
	// 容量不足でも自動削除・自動再起動は行わない。ここでは気づけるように表示するだけ。
	var STATUS_INTERVAL_MS = 60000;
	var DISK_WARN_PERCENT = 10;   // 空き割合がこれ未満で「警告」
	var DISK_ERROR_PERCENT = 5;   // 空き割合がこれ未満で「異常」
	var PLAYLIST_STALE_SEC = 30;  // ライブ用playlist.m3u8がこれ以上更新されなければ録画停止/停滞とみなす
	var STATUS_STALE_SEC = 180;   // status.json自体がこれ以上更新されなければ異常(cron停止・ディスク満杯など)

	var LEVEL_ORDER = { ok: 0, warn: 1, error: 2 };
	var LEVEL_MARK = { ok: '●', warn: '▲', error: '✖' };

	function pad2(n) {
		return (n < 10 ? '0' : '') + n;
	}

	function formatTime(sec) {
		var d = new Date(sec * 1000);
		return pad2(d.getHours()) + ':' + pad2(d.getMinutes()) + ':' + pad2(d.getSeconds());
	}

	function formatDuration(sec) {
		sec = Math.max(0, Math.round(sec));
		if (sec < 60) return sec + '秒';
		var min = Math.floor(sec / 60);
		if (min < 60) return min + '分';
		var hour = Math.floor(min / 60);
		return hour + '時間' + (min % 60 ? (min % 60) + '分' : '');
	}

	function formatBytes(bytes) {
		var units = ['B', 'KB', 'MB', 'GB', 'TB'];
		var v = bytes;
		var i = 0;
		while (v >= 1024 && i < units.length - 1) {
			v /= 1024;
			++i;
		}
		return v.toFixed(i === 0 ? 0 : 1) + ' ' + units[i];
	}

	// status.json の内容と「サーバの現在時刻(UNIX秒)」から、表示内容を決める。
	// 戻り値: { level: 'ok' | 'warn' | 'error', summary: 文字列, details: [警告文...] }
	function evaluateStatus(status, serverNowSec) {
		if (!status || typeof status !== 'object' || typeof status.generated_at !== 'number') {
			return { level: 'error', summary: '状態を判定できません', details: ['status.json の形式が不正です。'] };
		}

		var level = 'ok';
		var details = [];
		function raise(newLevel, message) {
			if (LEVEL_ORDER[newLevel] > LEVEL_ORDER[level]) level = newLevel;
			details.push(message);
		}

		var ffmpeg = status.ffmpeg || {};
		var disk = status.disk;

		// 録画状態: ライブ用プレイリストが更新され続けていれば録画中
		var playlistAge = (typeof ffmpeg.playlist_updated_at === 'number')
			? status.generated_at - ffmpeg.playlist_updated_at
			: null;
		var recording;
		if (playlistAge !== null && playlistAge <= PLAYLIST_STALE_SEC) {
			recording = '録画中';
		} else if (ffmpeg.process_alive === false) {
			recording = '停止';
			raise('error', 'ffmpegのプロセスがありません。録画は停止しています。ストレージの空き容量とffmpegのログを確認してください。');
		} else if (playlistAge !== null) {
			recording = '停滞';
			raise('error', 'ライブ用プレイリストが' + formatDuration(playlistAge) + '更新されていません。カメラとの接続やストレージの空き容量を確認してください。');
		} else {
			recording = '不明';
			raise('warn', 'ffmpegの状態を判定できません(PIDファイルもplaylist.m3u8も見つかりません)。');
		}

		// ストレージ
		var diskText;
		if (disk && typeof disk.free_percent === 'number' && typeof disk.free_bytes === 'number') {
			diskText = '空き ' + formatBytes(disk.free_bytes) + ' (' + disk.free_percent.toFixed(1) + '%)';
			if (disk.free_percent < DISK_ERROR_PERCENT) {
				raise('error', 'ストレージの空きが残りわずかです。録画が止まる恐れがあります。不要な録画を整理してください。');
			} else if (disk.free_percent < DISK_WARN_PERCENT) {
				raise('warn', 'ストレージの空きが少なくなっています。');
			}
		} else {
			diskText = '空き 不明';
			raise('warn', 'ストレージの容量を取得できていません。');
		}

		// status.json 自体の鮮度: 古ければ上の値は信用できない
		var statusAge = serverNowSec - status.generated_at;
		if (!(statusAge <= STATUS_STALE_SEC)) {
			raise('error', '状態の更新が' + formatDuration(statusAge) + '前から止まっています(status.plのcron停止やストレージ満杯の可能性)。上の値は古い情報です。');
		}

		return {
			level: level,
			summary: '録画: ' + recording + ' / ' + diskText + ' / 更新: ' + formatTime(status.generated_at),
			details: details
		};
	}

	var statusBox = document.getElementById('status');
	var statusSummary = document.getElementById('status-summary');
	var statusDetail = document.getElementById('status-detail');

	function renderStatus(result) {
		statusBox.className = 'status-' + result.level;
		statusSummary.textContent = LEVEL_MARK[result.level] + ' ' + result.summary;
		// 警告文は内容が変わったときだけ書き換える(読み上げの繰り返しを避ける)
		var key = result.details.join('\n');
		if (statusDetail.getAttribute('data-key') === key) return;
		statusDetail.setAttribute('data-key', key);
		statusDetail.textContent = '';
		for (var i = 0; i < result.details.length; ++i) {
			var line = document.createElement('div');
			line.textContent = result.details[i];
			statusDetail.appendChild(line);
		}
	}

	(function updateStatus() {
		fetch('status.json?' + (new Date()).getTime(), { cache: 'no-store' })
			.then(function (response) {
				if (!response.ok) throw new Error('HTTP ' + response.status);
				// 古さの判定は、端末の時計ではなく応答のDateヘッダ(サーバ時刻)を基準にする
				var serverMs = Date.parse(response.headers.get('Date'));
				if (isNaN(serverMs)) serverMs = Date.now();
				return response.json().then(function (status) {
					return { status: status, serverNowSec: serverMs / 1000 };
				});
			})
			.then(function (r) {
				renderStatus(evaluateStatus(r.status, r.serverNowSec));
			})
			.catch(function (e) {
				renderStatus({
					level: 'error',
					summary: '状態を取得できません',
					details: ['status.json を取得できませんでした(' + e.message + ')。サーバーまたは status.pl のcronを確認してください。']
				});
			})
			.finally(function () {
				setTimeout(updateStatus, STATUS_INTERVAL_MS);
			});
	})();

	var now = document.getElementById('now-stream');
	now.addEventListener('click', function () { playHLS('video', 'video/playlist.m3u8'); });
	now.click();

	(function updateRecord() {
		fetch('video/record.json?' + (new Date()).getTime())
			.then(function (response) {
				if (!response.ok) return;
				return response.text();
			})
			.then(function (text) {
				if (!text) return;
				try {
					buildRecord(JSON.parse(text));
				} catch (e) {
					// 破損JSONは再試行待ち
				}
			})
			.catch(function () {
				// ネットワークエラーは再試行待ち
			})
			.finally(function () {
				setTimeout(updateRecord, 60000);
			});
	})();

})();
