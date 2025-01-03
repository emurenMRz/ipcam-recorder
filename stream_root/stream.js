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

	var now = document.getElementById('now-stream');
	now.addEventListener('click', function () { playHLS('video', 'video/playlist.m3u8'); });
	now.click();

	(function updateRecord() {
		var xhr = new XMLHttpRequest();
		xhr.addEventListener('load', function () {
			if (xhr.readyState == 4 && xhr.status == 200)
				buildRecord(JSON.parse(xhr.responseText));
		});
		xhr.open('GET', 'video/record.json?' + (new Date()).getTime());
		xhr.send(null);
		setTimeout(updateRecord, 60000);
	})();

})();
