extends RefCounted
# Godot refuses NUL and lone UTF16 surrogates. Preserve source code units
# with an injective internal String codec; escape the marker itself as well.
const MARKER="\uE000"
static func native_units(text):
	var units=[]
	for i in text.length():
		var point=text.unicode_at(i)
		if point>0xffff:units.append(0xd800+((point-0x10000)>>10));units.append(0xdc00+((point-0x10000)&1023))
		else:units.append(point)
	return units
static func from_units(units):
	var text="";var i=0
	while i<units.size():
		var unit=int(units[i]);i+=1
		if unit>=0xd800 and unit<=0xdbff and i<units.size() and units[i]>=0xdc00 and units[i]<=0xdfff:
			text+=String.chr(0x10000+((unit-0xd800)<<10)+(int(units[i])-0xdc00));i+=1
		elif unit==0 or unit==0xe000 or (unit>=0xd800 and unit<=0xdfff):text+=MARKER+"%04x;"%unit
		else:text+=String.chr(unit)
	return text
static func encode_native(text):return from_units(native_units(text))
static func utf16_units(text):
	var units=[];var i=0
	while i<text.length():
		var point=text.unicode_at(i);i+=1
		if point==0xe000 and i+4<text.length() and text[i+4]==";":
			var hexadecimal=text.substr(i,4);var unit=hexadecimal.hex_to_int()
			if hexadecimal=="%04x"%unit and (unit==0 or unit==0xe000 or (unit>=0xd800 and unit<=0xdfff)):units.append(unit);i+=5;continue
		if point>0xffff:units.append(0xd800+((point-0x10000)>>10));units.append(0xdc00+((point-0x10000)&1023))
		else:units.append(point)
	return units
static func source_length(text):return utf16_units(text).size()
static func whitespace(unit):return unit in [9,10,11,12,13,32,0xa0,0x1680,0x2028,0x2029,0x202f,0x205f,0x3000,0xfeff] or (unit>=0x2000 and unit<=0x200a)
static func source_trim(text):
	var units=utf16_units(text);var first=0;var last=units.size()
	while first<last and whitespace(units[first]):first+=1
	while last>first and whitespace(units[last-1]):last-=1
	return from_units(units.slice(first,last))
static func less(left,right):
	var a=utf16_units(left);var b=utf16_units(right)
	for i in min(a.size(),b.size()):
		if a[i]!=b[i]:return a[i]<b[i]
	return a.size()<b.size()
static func display_text(text):
	var units=utf16_units(text);var result="";var i=0
	while i<units.size():
		var unit=units[i];i+=1
		if unit>=0xd800 and unit<=0xdbff and i<units.size() and units[i]>=0xdc00 and units[i]<=0xdfff:
			result+=String.chr(0x10000+((unit-0xd800)<<10)+(units[i]-0xdc00));i+=1
		elif unit==0 or (unit>=0xd800 and unit<=0xdfff):result+="\\u%04x"%unit
		else:result+=String.chr(unit)
	return result
static func json_string(text):
	var units=utf16_units(text);var result="\"";var i=0
	while i<units.size():
		var unit=units[i];i+=1
		if unit in [8,9,10,12,13,34,92]:result+={8:"\\b",9:"\\t",10:"\\n",12:"\\f",13:"\\r",34:"\\\"",92:"\\\\"}[unit]
		elif unit<32:result+="\\u%04x"%unit
		elif unit>=0xd800 and unit<=0xdbff and i<units.size() and units[i]>=0xdc00 and units[i]<=0xdfff:
			result+=String.chr(0x10000+((unit-0xd800)<<10)+(units[i]-0xdc00));i+=1
		elif unit>=0xd800 and unit<=0xdfff:result+="\\u%04x"%unit
		else:result+=String.chr(unit)
	return result+"\""
