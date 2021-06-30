document.querySelectorAll("form").forEach(form => {
	form.addEventListener("submit", (e) => {
		e.preventDefault();
		fetch(form.action, {
			method: form.method,
			body: new FormData(form)
		})
		.then(r => r.text())
		.then(text => {
			if (text.includes("/")) {
				window.location.href = text;
			} else {
				form.querySelector(".error").innerHTML = text;
			}
		});
	});
});