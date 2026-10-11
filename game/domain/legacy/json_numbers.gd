extends RefCounted
# Strict JSON syntax, with ECMAScript binary64 rounding instead of Godot's
# approximate numeric reader. UTF16 strings use the lossless legacy codec.
const Numbers=preload("res://game/domain/legacy/surrender.gd")
const Text=preload("res://game/domain/legacy/utf16_text.gd")
var source=[]
var cursor=0
var valid=true
func decode(text,encoded_input=false):
	if not text is String:return {"ok":false}
	source=Text.utf16_units(text) if encoded_input else Text.native_units(text);cursor=0;valid=true
	var value=read_value();space()
	return {"ok":valid and cursor==source.size(),"value":value}
func peek():return String.chr(source[cursor]) if cursor<source.size() and source[cursor]>0 and not (source[cursor]>=0xd800 and source[cursor]<=0xdfff) else ""
func space():
	while cursor<source.size() and source[cursor] in [32,9,13,10]:cursor+=1
func take(character):
	space()
	if cursor<source.size() and source[cursor]==character.unicode_at(0):cursor+=1;return true
	valid=false;return false
func digit():return cursor<source.size() and source[cursor]>=48 and source[cursor]<=57
func hex_digit(unit):
	if unit>=48 and unit<=57:return unit-48
	if unit>=65 and unit<=70:return unit-55
	if unit>=97 and unit<=102:return unit-87
	return -1
func read_string():
	cursor+=1;var units=[]
	while cursor<source.size():
		var unit=source[cursor];cursor+=1
		if unit<32:valid=false;return null
		if unit==34:return Text.from_units(units)
		if unit!=92:units.append(unit);continue
		if cursor>=source.size():valid=false;return null
		var escape=source[cursor];cursor+=1
		if escape==117:
			if cursor+4>source.size():valid=false;return null
			var code=0
			for _i in 4:
				var digit_value=hex_digit(source[cursor]);cursor+=1
				if digit_value<0:valid=false;return null
				code=(code<<4)|digit_value
			units.append(code)
		elif escape in [34,92,47,98,102,110,114,116]:units.append({34:34,92:92,47:47,98:8,102:12,110:10,114:13,116:9}[escape])
		else:valid=false;return null
	valid=false;return null
func read_value():
	space()
	if cursor>=source.size():valid=false;return null
	var character=peek()
	if character=="\"":return read_string()
	if character=="{":
		cursor+=1;space();var value={}
		if cursor<source.size() and source[cursor]==125:cursor+=1;return value
		while valid:
			space()
			if cursor>=source.size() or source[cursor]!=34:valid=false;return null
			var key=read_string()
			if not valid or not take(":"):return null
			value[key]=read_value();space()
			if cursor<source.size() and source[cursor]==125:cursor+=1;return value
			if not take(","):return null
		return null
	if character=="[":
		cursor+=1;space();var value=[]
		if cursor<source.size() and source[cursor]==93:cursor+=1;return value
		while valid:
			value.append(read_value());space()
			if cursor<source.size() and source[cursor]==93:cursor+=1;return value
			if not take(","):return null
		return null
	for literal in {"true":true,"false":false,"null":null}:
		if source.slice(cursor,cursor+literal.length())==Text.native_units(literal):cursor+=literal.length();return {"true":true,"false":false,"null":null}[literal]
	var start=cursor
	if character=="-":cursor+=1
	if not digit():valid=false;return null
	if source[cursor]==48:cursor+=1
	else:
		while digit():cursor+=1
	if cursor<source.size() and source[cursor]==46:
		cursor+=1
		if not digit():valid=false;return null
		while digit():cursor+=1
	if cursor<source.size() and source[cursor] in [101,69]:
		cursor+=1
		if cursor<source.size() and source[cursor] in [43,45]:cursor+=1
		if not digit():valid=false;return null
		while digit():cursor+=1
	return Numbers.parse_number(Text.from_units(source.slice(start,cursor)))
