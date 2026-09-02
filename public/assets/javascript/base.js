var Fluence = {
	editor : {
		isPreviewActive: false
	}
};

// The EasyMDE instance of the page editor, once initialized.
var editor;

// Creates the page editor in edit or preview mode, then reveals the form
// (hidden until now so the mode switch happens out of sight).
//
// A draft left by an earlier visit is restored by EasyMDE; the editor then
// opens in edit mode behind a notice offering to discard it. A draft equal
// to the saved page is dropped silently, and no draft is kept until the
// content is actually changed, so the notice appears only for real edits.
Fluence.editor.init = function(open_in_edit) {
	var saved = document.querySelector("#edit-page textarea").value;
	editor = new EasyMDE(Fluence.mde_options(true));
	var draft = editor.options.autosave.foundSavedValue === true;
	if (draft && editor.value() === saved)
		draft = false;
	if (!draft)
		Fluence.editor.dropDraft();
	else {
		open_in_edit = true;
		document.getElementById("draft-notice").hidden = false;
	}
	if (open_in_edit)
		editor.codemirror.focus();
	else
		Fluence.editor.togglePreview();
	document.getElementById("edit-page").classList.remove("invisible");
}

// Removes the stored draft, including one EasyMDE is about to write, and
// the "Autosaved" note in the status bar that went with it.
Fluence.editor.dropDraft = function() {
	clearTimeout(editor._autosave_timeout);
	editor.clearAutosavedValue();
	var note = document.querySelector(".editor-statusbar .autosave");
	if (note) note.textContent = "";
}

// "Discard draft" on the notice: forget the draft and reload the saved page.
Fluence.editor.discardDraft = function() {
	Fluence.editor.dropDraft();
	location.replace(location.pathname + "?edit");
}

// "Save and continue": saves over fetch and keeps editing, with cursor,
// scroll position, and mode intact. The server answers JSON when asked
// for it. Returns false so the button does not submit the form (without
// JavaScript the same button submits normally and the editor reopens).
Fluence.editor.saveAndContinue = function(form) {
	var summary = document.getElementById("input-summary");
	var status = document.getElementById("save-status");
	status.textContent = "Saving…";
	fetch(form.action, {
		method: "POST",
		headers: { "Accept": "application/json" },
		body: new URLSearchParams({ "body": editor.value(), "summary": summary.value, "continue": "1" })
	})
		.then(function(response) { return response.json(); })
		.then(function(result) {
			if (result.success) {
				Fluence.editor.dropDraft();
				summary.value = "";
				status.textContent = "Saved " + new Date().toLocaleTimeString();
			} else
				status.textContent = "Not saved: " + (result.error || "unknown error");
		})
		.catch(function(error) { status.textContent = "Not saved: " + error; });
	return false;
}

Fluence.mde_options = function(can_edit) {
	options = {
		// All assets are served locally; never let the editor pull
		// Font Awesome or spell-checker dictionaries from a CDN.
		autoDownloadFontAwesome: false,
		spellChecker: false,
		renderingConfig: { codeSyntaxHighlighting: true },
		status: ["autosave", "lines", "words", "cursor"],
		shortcuts: { drawTable: "Cmd-Alt-T", undo: "Cmd-Z", redo: "Cmd-Y" },
		// Unsaved edits are kept as a draft in the browser's localStorage,
		// keyed by page path, and restored on the next visit (see
		// Fluence.editor.init); saving the page discards the draft.
		autosave: { enabled: true, delay: 3000, uniqueId: location.pathname },
		// Do not use placeholder because it only shows in Edit mode,
		// and it is not needed there.
		//placeholder: "Please enter Edit mode to add content",
		toolbar: [
			"fullscreen"
		]
	};
	if(can_edit) {
		options["toolbar"].push(
			{ name: "preview", action: Fluence.editor.togglePreview, className: "fa fa-eye", noDisable: true, title: "Preview" },
			"side-by-side",
			"|",
			"bold",
			"italic",
			"strikethrough",
			"heading-smaller",
			"heading-bigger",
			"|",
			"code",
			"quote",
			"unordered-list",
			"ordered-list",
			"|",
			"link",
			"image",
			"table",
			"horizontal-rule",
			"|",
			{ name: "clean-block", action: EasyMDE.cleanBlock, className: "fa fa-eraser fa-clean-block", title: "Clear formatting" },
			{ name: "undo", action: EasyMDE.undo, className: "fa fa-undo", title: "Undo" },
			{ name: "redo", action: EasyMDE.redo, className: "fa fa-redo", title: "Redo" }
		);
	};
	return options
}

// Switches the editor between preview and edit mode. Save and the change
// summary only make sense while editing, so they are hidden in preview.
Fluence.editor.togglePreview = function(){
	editor.togglePreview();
	Fluence.editor.isPreviewActive = !Fluence.editor.isPreviewActive;
	var editing = !Fluence.editor.isPreviewActive;
	document.getElementById("button_toggle").textContent = editing ? "Preview" : "Edit";
	document.getElementById("button_save").hidden = !editing;
	document.getElementById("edit-extras").hidden = !editing;
	if (editing) editor.codemirror.focus();
}

// Click handler of an attachment's Delete button: deletes over fetch and
// removes the row without reloading the page. The button's form action is
// the attachment URL; the server answers JSON when asked for it.
Fluence.deleteAttachment = function(button, name) {
	if (!confirm("Really delete attachment `" + name + "`?")) return false;
	var row = button.closest(".row");
	fetch(button.formAction, {
		method: "POST",
		headers: { "Accept": "application/json" },
		body: new URLSearchParams({ "delete": "Delete", "media-name": name })
	})
		.then(function(response) { return response.json(); })
		.then(function(result) {
			if (result.success)
				row.remove();
			else
				Fluence.markRowFailed(row, result.error);
		})
		.catch(function(error) { Fluence.markRowFailed(row, String(error)); });
	return false;
}

Fluence.markRowFailed = function(row, error) {
	row.classList.add("text-danger");
	row.title = error || "Delete failed";
}

// Submit handler of the attachment form on a page: uploads each selected
// file to /media/upload and appends the outcome to the attachment list.
Fluence.upload = function(form) {
	var input = form.querySelector('input[type="file"]');
	Array.from(input.files).forEach(function(file) {
		var data = new FormData();
		data.append("pagename", form.dataset.pagename);
		data.append("file", file, file.name);
		fetch(form.action, { method: "POST", body: data })
			.then(function(response) { return response.json(); })
			.then(function(result) {
				if (result.success)
					Fluence.attachmentRow(result.name, result.url);
				else
					Fluence.attachmentError(file.name, result.error);
			})
			.catch(function(error) {
				Fluence.attachmentError(file.name, String(error));
			});
	});
	input.value = "";
	return false;
}

// A successfully uploaded attachment: link plus a Delete button,
// matching the server-rendered rows in views/pages/show.slang.
Fluence.attachmentRow = function(name, url) {
	var row = Fluence.appendAttachment(name, "row border-bottom", "");
	var link = row.querySelector("a");
	link.href = url;

	var hidden = document.createElement("input");
	hidden.type = "hidden";
	hidden.name = "media-name";
	hidden.value = name;

	var button = document.createElement("button");
	button.className = "btn btn-sm btn-danger my-1";
	button.type = "submit";
	button.name = "delete";
	button.value = "Delete";
	button.formAction = url;
	button.textContent = "Delete";
	button.onclick = function() {
		return Fluence.deleteAttachment(button, name);
	};

	var right = row.lastElementChild;
	right.appendChild(hidden);
	right.appendChild(button);
}

Fluence.attachmentError = function(name, error) {
	var row = Fluence.appendAttachment(name, "row border-bottom text-danger", "FAILED");
	row.title = error || "Upload failed";
}

Fluence.appendAttachment = function(name, rowClass, rightText) {
	var row = document.createElement("div");
	row.className = rowClass;

	var left = document.createElement("div");
	left.className = "col-9";
	var link = document.createElement("a");
	link.className = "list-group-item";
	link.textContent = name;
	left.appendChild(link);

	var right = document.createElement("div");
	right.className = "col-3";
	right.textContent = rightText;

	row.appendChild(left);
	row.appendChild(right);
	document.getElementById("attachments").appendChild(row);
	return row;
}
