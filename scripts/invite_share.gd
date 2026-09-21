extends RefCounted
## Share the existing private-lobby code. No new codes, deep links, or a text-message handoff.
##
## Copy: DisplayServer.clipboard_set of the 6-char code.
## Share: prefer a built-in OS share sheet.
##   - DisplayServer.share_text / OS.share_text if a future Godot build adds one.
##   - Android ACTION_SEND chooser via JavaClassWrapper + AndroidRuntime (Godot 4.4+).
## Godot 4.3–4.6 has no desktop share sheet. Linux, macOS, Windows, web, and iOS
## copy the short blurb and the wait plate toasts. A URI opener is not used:
## it would open a link or a message-app handler, which this slice does not do.

const Contract := preload("res://types/contract.gd")

const RESULT_SHEET := "sheet"
const RESULT_CLIPBOARD := "clipboard"
const RESULT_NONE := ""


static func blurb_for(code: String) -> String:
	var norm := Contract.normalize_lobby_code(code)
	return Contract.LOBBY_SHARE_BLURB % norm


static func copy_code(code: String) -> bool:
	## Puts the raw 6-char code on the clipboard. Display spacing stays on the plate.
	var norm := Contract.normalize_lobby_code(code)
	if not Contract.is_lobby_code(norm):
		return false
	return _clipboard_set(norm)


static func share_code(code: String) -> String:
	## "sheet" when an OS share sheet opened with the blurb.
	## "clipboard" on the copy-only fallback (desktop and any platform without a sheet).
	## "" when the code is not a lobby code — nothing is shared or copied.
	var norm := Contract.normalize_lobby_code(code)
	if not Contract.is_lobby_code(norm):
		return RESULT_NONE
	var blurb := blurb_for(norm)
	if open_share_sheet(blurb):
		return RESULT_SHEET
	if _clipboard_set(blurb):
		return RESULT_CLIPBOARD
	return RESULT_NONE


static func open_share_sheet(text: String) -> bool:
	if text == "":
		return false
	if _builtin_share(text):
		return true
	if OS.has_feature("android"):
		return _android_share_sheet(text)
	return false


static func _clipboard_set(text: String) -> bool:
	DisplayServer.clipboard_set(text)
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		return DisplayServer.clipboard_get() == text
	## Headless / web without a clipboard feature still issued the set.
	return true


static func _builtin_share(text: String) -> bool:
	## Probe only. Godot 4.5 DisplayServer has clipboard, not a share sheet.
	if DisplayServer.has_method("share_text"):
		DisplayServer.call("share_text", text)
		return true
	if OS.has_method("share_text"):
		OS.call("share_text", text)
		return true
	return false


static func _android_share_sheet(text: String) -> bool:
	## Built-in engine bridge. Not a third-party share plugin. Text only — no URI.
	if not Engine.has_singleton("AndroidRuntime"):
		return false
	var runtime = Engine.get_singleton("AndroidRuntime")
	if runtime == null or not runtime.has_method("getActivity"):
		return false
	var activity = runtime.call("getActivity")
	if activity == null:
		return false
	var Intent = JavaClassWrapper.wrap("android.content.Intent")
	if Intent == null:
		return false
	## Constructor is the class name. Chooser is the OS share sheet. Text only.
	var intent = Intent.Intent()
	if intent == null:
		return false
	intent.setAction(Intent.ACTION_SEND)
	intent.putExtra(Intent.EXTRA_TEXT, text)
	intent.setType("text/plain")
	var chooser = Intent.createChooser(intent, "Hunt with me")
	if chooser == null:
		return false
	if runtime.has_method("createRunnableFromGodotCallable") and activity.has_method("runOnUiThread"):
		var start := func() -> void:
			activity.startActivity(chooser)
		activity.runOnUiThread(runtime.createRunnableFromGodotCallable(start))
	else:
		activity.startActivity(chooser)
	return true
