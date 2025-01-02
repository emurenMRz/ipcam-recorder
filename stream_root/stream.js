function playHLS(id, name) {
	const video = document.getElementById(id);
	if (video.canPlayType('application/vnd.apple.mpegurl')) {
		video.src = name;
		video.addEventListener('loadedmetadata', () => video.play());
	} else if (Hls.isSupported()) {
		const hls = new Hls();
		hls.loadSource(name);
		hls.attachMedia(video);
		hls.on(Hls.Events.MANIFEST_PARSED, () => video.play());
	}
}

function playRecord() {
	playHLS('video', `video/${this.getAttribute('data-src')}`);
}

function buildRecord(json) {
	const list = document.getElementById('record');
	list.textContent = '';
	json.sort((a, b) => b.date - a.date).forEach(({ date, hours }) => {
		const mat = date.match(/^(?<Y>[0-9]{4})(?<M>[0-9]{2})(?<D>[0-9]{2})$/);
		if (!mat) throw new Error(`unsupport date format: ${date}`);
		const { Y, M, D } = mat.groups;
		const dt = document.createElement('dt');
		dt.textContent = `${Y}-${M}-${D}`;
		list.appendChild(dt);

		var dd = document.createElement('dd');
		hours.sort((a, b) => b.hour - a.hour).forEach(({ thumb, path, hour }) => {
			const thumbnail = document.createElement('img');
			thumbnail.className = 'thumbnail';
			thumbnail.src = `video/${thumb}`;
			thumbnail.setAttribute('data-src', `video/${path}`);
			thumbnail.onclick = playRecord;
			const title = document.createElement('span');
			title.className = 'title';
			title.textContent = `${hour}:00`;
			const box = document.createElement('div');
			box.appendChild(thumbnail);
			box.appendChild(title);
			dd.appendChild(box);
		});
		list.appendChild(dd);
	});
}

addEventListener('DOMContentLoaded', () => {
	const now = document.getElementById('now-stream');
	now.addEventListener('click', () => playHLS('video', 'video/playlist.m3u8'));
	now.click();

	const updateRecord = () => {
		fetch(`video/record.json?${(new Date()).getTime()}`)
			.then(r => r.json())
			.then(buildRecord)
			.catch(console.error);
		setTimeout(updateRecord, 60 * 1000);
	};
	updateRecord();
});

