extends RefCounted
## One clipboard read for a bare 6-char lobby code.
##
## The join plate calls peek_code when the form opens and when it gains focus.
## It does not poll. A Paste tap fills the field; this script does not join,
## mint a code, scrape a message, or open a link.

const Contract := preload("res://types/contract.gd")


static func peek_code() -> String:
	return code_from_text(_clipboard_get())


static func code_from_text(raw: String) -> String:
	## The whole clipboard must be a lobby code. Spaces and dashes are display noise.
	## A sentence, a share blurb, or a link is not a code.
	var trimmed := raw.strip_edges()
	if trimmed == "":
		return ""
	if not _bare_code_text(trimmed):
		return ""
	var norm := Contract.normalize_lobby_code(trimmed)
	if not Contract.is_lobby_code(norm):
		return ""
	return norm


static func fill_text(field_text: String, peeked: String) -> String:
	## Chip tap. An empty or invalid peek leaves the field alone.
	if not Contract.is_lobby_code(peeked):
		return field_text
	return Contract.normalize_lobby_code(peeked)


static func _bare_code_text(text: String) -> bool:
	for i in text.length():
		var ch := text.substr(i, 1).to_upper()
		if ch == " " or ch == "-" or ch == "_":
			continue
		if Contract.LOBBY_CODE_ALPHABET.find(ch) < 0:
			return false
	return true


static func _clipboard_get() -> String:
	return str(DisplayServer.clipboard_get())
