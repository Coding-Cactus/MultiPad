window.onload = () => {
	String.prototype.insertAt = function(index, insert) {
		return this.substr(0, index) + insert + this.substr(index);
	}

	String.prototype.removeAt = function(index, length) {
		return this.substr(0, index) + this.substr(index + length);
	}

	function popup(good, msg) {
		const pop = document.createElement("div");

		pop.innerText = msg;
		pop.className = good ? "good-popup" : "bad-popup";

		document.body.appendChild(pop);

		setTimeout(() => {
			pop.remove();
		}, 4000);
	}


	const textarea = document.querySelector("textarea");
	const ws = new WebSocket("wss://" + window.location.hostname + window.location.pathname);

	setInterval(() => {
		if (ws.readyState === WebSocket.OPEN) {
			if (textarea.disabled) {
				textarea.disabled = false;
				popup(true, "Connected");
			}
		} else if (!textarea.disabled) {
			textarea.disabled = true;
			popup(false, "Disconnected");
		}
	});
	
	let oldContentLength = textarea.value.length;

	ws.onmessage = (msg) => {
		const start = textarea.selectionStart;
		const end = textarea.selectionEnd;
		const data = JSON.parse(msg.data);
		if (data["type"] === "addition") {
			textarea.value = textarea.value.insertAt(data["selection_start"], data["data"]);
			if (data["selection_start"] <= start) {
				textarea.setSelectionRange(start+data["data"].length, end+data["data"].length);
			} else {
				textarea.setSelectionRange(start, end);
			}
		} else if (data["type"] === "subtraction" || (data["type"] === "error" && data["error"] === "storage")) {
			textarea.value = textarea.value.removeAt(data["selection_start"], data["length"]);
			if (data["selection_start"] <= start) {
				textarea.setSelectionRange(start-data["length"], end-data["length"]);
			} else {
				textarea.setSelectionRange(start, end);
			}

			if (data["type"] === "error") {
				popup(false, "Character limit of " + data["limit"] + " exceeded");
			}
		}
		else {
			document.getElementById("users-online").innerHTML = data["num"];
		}
		oldContentLength = textarea.value.length;
	}

	function send_addition(data, selectionStart) {
		ws.send(JSON.stringify({
			data: data,
			selection_start: selectionStart,
			type: "addition"
		}));
	}

	function send_subtraction(length, selectionStart) {
		ws.send(JSON.stringify({
			length: length,
			selection_start: selectionStart,
			type: "subtraction"
		}));
	}
	
	textarea.addEventListener("input", () => {
		if (textarea.value.length > oldContentLength) {
			const textStart = textarea.selectionStart - (textarea.value.length - oldContentLength);
			const textLength = textarea.value.length - oldContentLength;
			send_addition(textarea.value.substr(textStart, textLength), textStart);
		} else if (oldContentLength > textarea.value.length) {
			send_subtraction(oldContentLength - textarea.value.length, textarea.selectionStart);
		}
		oldContentLength = textarea.value.length;
	});
}