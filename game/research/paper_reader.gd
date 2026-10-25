extends RefCounted
## Small read-only Markdown presentation. No command execution, URLs or BBCode from paper data.
const Parchment = preload("res://game/ui/shared/parchment_theme.gd")
static func escape(value: String) -> String: return value.replace("[","[lb]")
static func _inline(value: String) -> String:
	var parts := value.split("`"); var result := ""
	for i in parts.size():
		if i%2 == 1: result += "[code]"+escape(parts[i])+"[/code]"
		else:
			var bold := parts[i].split("**")
			for j in bold.size(): result += ("[b]" if j%2 else "")+escape(bold[j])+("[/b]" if j%2 else "")
	return result

static func to_bbcode(markdown: String) -> String:
	var lines := markdown.replace("\r","").split("\n"); var result := ""; var in_code := false
	for line: String in lines:
		if line.begins_with("```"):
			result += "[/code][/color]\n" if in_code else "[color=#%s][code]" % Parchment.SEA.to_html(false)
			in_code = not in_code; continue
		if in_code: result += escape(line)+"\n"; continue
		if line.begins_with("# "): result += "[font_size=28][b]"+_inline(line.substr(2))+"[/b][/font_size]\n\n"
		elif line.begins_with("## "): result += "\n[color=#%s][font_size=22][b]" % Parchment.CINNABAR.to_html(false)+_inline(line.substr(3))+"[/b][/font_size][/color]\n\n"
		elif line.begins_with("### "): result += "\n[b]"+_inline(line.substr(4))+"[/b]\n"
		elif line.begins_with("- "): result += "• "+_inline(line.substr(2))+"\n"
		elif line.begins_with("> "): result += "[color=#%s]" % Parchment.MUTED.to_html(false)+_inline(line.substr(2))+"[/color]\n"
		else: result += _inline(line)+"\n"
	if in_code: result += "[/code][/color]"
	return result
