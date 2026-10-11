extends RefCounted
const Text=preload("res://game/domain/legacy/utf16_text.gd")
const GOODS=["grain","wood","iron","silk","porcelain","spices"]
static func cargo(value):
	var result={}
	for g in GOODS:result[g]=value[g]
	return result
static func ordered(items,key):
	var result=items.duplicate();result.sort_custom(func(a,b):return Text.less(a[key],b[key]));return result
static func canonical_terms(t):
	var terms={"captor":{"id":t.captor.id,"name":t.captor.name,"faction":t.captor.faction},"returnPortId":t.returnPortId,"silver":{"before":t.silver.before,"loss":t.silver.loss,"after":t.silver.after},"morale":{"before":t.morale.before,"after":t.morale.after},"fame":{"before":t.fame.before,"after":t.fame.after},"relation":{"before":t.relation.before,"after":t.relation.after},"shipLosses":[],"lostShips":[],"failedQuests":[],"completedQuestIds":t.completedQuestIds.duplicate(),"mainChapter":t.mainChapter,"surrenders":{"before":t.surrenders.before,"after":t.surrenders.after}}
	for s in ordered(t.shipLosses,"shipId"):terms.shipLosses.append({"shipId":s.shipId,"name":s.name,"before":cargo(s.before),"loss":cargo(s.loss),"after":cargo(s.after),"hull":s.hull,"maxHull":s.maxHull,"sail":s.sail,"crew":s.crew,"ammo":{"solid":s.ammo.solid,"chain":s.ammo.chain,"grape":s.ammo.grape}})
	for s in ordered(t.lostShips,"id"):terms.lostShips.append({"id":s.id,"name":s.name,"kind":s.kind})
	for q in ordered(t.failedQuests,"id"):terms.failedQuests.append({"id":q.id,"title":q.title,"before":q.before})
	terms.completedQuestIds.sort_custom(Text.less);return Text.encode_native(js_json(terms))
static func js_json(value):
	if value is Dictionary:
		var entries=[]
		for key in value:entries.append(Text.json_string(str(key))+":"+js_json(value[key]))
		return "{"+",".join(entries)+"}"
	if value is Array:
		var entries=[]
		for item in value:entries.append(js_json(item))
		return "["+",".join(entries)+"]"
	if typeof(value)==TYPE_FLOAT:
		return number_text(value)
	if value is String:return Text.json_string(value)
	return JSON.stringify(value,"",false,true)
static func multiply_small(limbs,factor):
	var carry=0
	for i in limbs.size():
		var product=limbs[i]*factor+carry
		limbs[i]=product%1000000000;carry=int(product/1000000000)
	if carry!=0:limbs.append(carry)
static func binary_decimal(mantissa,binary_power):
	# Base-1e9 limbs represent m * 2^e exactly without a floating parser.
	var limbs=[]
	while mantissa>0:limbs.append(mantissa%1000000000);mantissa=int(mantissa/1000000000)
	var scale=max(0,-binary_power)
	for _i in abs(binary_power):multiply_small(limbs,5 if binary_power<0 else 2)
	var digits=str(limbs[-1])
	for i in range(limbs.size()-2,-1,-1):digits+="%09d"%limbs[i]
	return {"digits":digits,"exponent":digits.length()-scale-1}
static func compare_decimal(coefficient,power,boundary):
	return compare_digits(str(coefficient),power+str(coefficient).length()-1,boundary)
static func compare_digits(digits,exponent,boundary):
	if boundary.digits=="0":return 0 if digits=="0" else 1
	if exponent!=boundary.exponent:return -1 if exponent<boundary.exponent else 1
	var width=max(digits.length(),boundary.digits.length())
	var left=digits+"0".repeat(width-digits.length())
	var right=boundary.digits+"0".repeat(width-boundary.digits.length())
	return 0 if left==right else (-1 if left<right else 1)
static func float_bits(value):
	var bytes=PackedFloat64Array([value]).to_byte_array();var bits=0
	for i in 8:bits|=int(bytes[i])<<(8*i)
	return bits
static func bits_float(bits):
	var bytes=PackedByteArray();bytes.resize(8)
	for i in 8:bytes[i]=(bits>>(8*i))&255
	return bytes.to_float64_array()[0]
static func rounding_interval(bits):
	var exponent=(bits>>52)&2047;var mantissa=bits&((1<<52)-1)
	var binary_power=-1074 if exponent==0 else exponent-1075
	if exponent!=0:mantissa|=1<<52
	var lower={"digits":"0","exponent":0} if bits==0 else (binary_decimal(4*mantissa-1,binary_power-2) if exponent>1 and mantissa==(1<<52) else binary_decimal(2*mantissa-1,binary_power-1))
	return {"lower":lower,"upper":binary_decimal(2*mantissa+1,binary_power-1),"ties":mantissa%2==0,"mantissa":mantissa,"power":binary_power}
static func parse_number(token):
	# Godot's decimal parser can miss a binary64 neighbor. Correct its estimate
	# against exact midpoints so source JSON numbers retain their original bits.
	var negative=token.begins_with("-");var unsigned=token.substr(1) if negative else token
	if unsigned.length()<=15 and not "." in unsigned and not "e" in unsigned.to_lower():return -0.0 if negative and int(unsigned)==0 else float(int(token))
	var parts=unsigned.to_lower().split("e");var exponent=0
	if parts.size()>1:
		var exp_text=parts[1];var exp_digits=exp_text.trim_prefix("-").trim_prefix("+")
		while exp_digits.begins_with("0"):exp_digits=exp_digits.substr(1)
		exponent=(-100000 if exp_text.begins_with("-") else 100000) if exp_digits.length()>6 else int(exp_text)
	var point=parts[0].find(".");var fraction=parts[0].length()-point-1 if point>=0 else 0
	var digits=parts[0].replace(".","")
	while digits.length()>1 and digits.begins_with("0"):digits=digits.substr(1)
	if digits=="0":return -0.0 if negative else 0.0
	exponent+=digits.length()-fraction-1
	while digits.length()>1 and digits.ends_with("0"):digits=digits.left(-1)
	if exponent>309:return -INF if negative else INF
	if exponent< -324:return -0.0 if negative else 0.0
	var estimate=abs(token.to_float());var bits=0x7fefffffffffffff if is_inf(estimate) else float_bits(estimate)
	var low_bits=0;var high_bits=0x7fefffffffffffff
	for iteration in 160:
		var interval=rounding_interval(bits)
		var low=compare_digits(digits,exponent,interval.lower);var high=compare_digits(digits,exponent,interval.upper)
		if low<0 or (low==0 and not interval.ties):
			high_bits=bits-1;bits=bits-1 if iteration<16 else low_bits+((high_bits-low_bits)>>1)
		elif high>0 or (high==0 and not interval.ties):
			if bits==0x7fefffffffffffff:return -INF if negative else INF
			low_bits=bits+1;bits=bits+1 if iteration<16 else low_bits+((high_bits-low_bits)>>1)
		else:return -bits_float(bits) if negative else bits_float(bits)
	assert(false,"No binary64 rounding interval for JSON decimal")
	return NAN
static func within_rounding_interval(coefficient,power,lower,upper,include_ties):
	if coefficient<=0:return false
	var low=compare_decimal(coefficient,power,lower);var high=compare_decimal(coefficient,power,upper)
	return (low>0 or (low==0 and include_ties)) and (high<0 or (high==0 and include_ties))
static func decimal_text(coefficient,power):
	var digits=str(coefficient)
	while digits.length()>1 and digits.ends_with("0"):digits=digits.left(-1);power+=1
	var exponent=power+digits.length()-1
	if exponent<-6 or exponent>=21:
		return digits[0]+("."+digits.substr(1) if digits.length()>1 else "")+"e"+("+" if exponent>=0 else "")+str(exponent)
	var point=digits.length()+power
	if point<=0:return "0."+"0".repeat(-point)+digits
	if point>=digits.length():return digits+"0".repeat(point-digits.length())
	return digits.left(point)+"."+digits.substr(point)
static func number_text(value):
	if not is_finite(value):return "null"
	if value==0:return "0"
	var prefix="-" if value<0 else "";var magnitude=abs(value)
	if magnitude<=9007199254740991.0 and magnitude==floor(magnitude):return prefix+str(int(magnitude))
	var interval=rounding_interval(float_bits(magnitude));var exact=binary_decimal(interval.mantissa,interval.power)
	# Midpoints of adjacent binary64 values define precisely which decimals
	# round to this value. Powers of two have a smaller preceding spacing.
	var lower=interval.lower;var upper=interval.upper;var include_ties=interval.ties
	# ECMAScript chooses the fewest significant digits, then the nearest
	# decimal (ties even). Binary64 always has a candidate within 17 digits.
	for precision in range(1,18):
		var digits=exact.digits;var coefficient=int(digits.left(precision))
		if digits.length()<precision:coefficient*=int(pow(10,precision-digits.length()))
		if digits.length()>precision:
			var next_digit=digits.unicode_at(precision)-48;var remainder_nonzero=false
			for i in range(precision+1,digits.length()):
				if digits[i]!="0":remainder_nonzero=true;break
			if next_digit>5 or (next_digit==5 and (remainder_nonzero or coefficient%2==1)):coefficient+=1
		var power=exact.exponent-precision+1
		if within_rounding_interval(coefficient,power,lower,upper,include_ties):return prefix+decimal_text(coefficient,power)
		# The interval is asymmetric at powers of two; the nearest decimal can
		# sit outside its narrow side while its immediate neighbor is inside.
		for neighbor in [coefficient-1,coefficient+1]:
			if within_rounding_interval(neighbor,power,lower,upper,include_ties):return prefix+decimal_text(neighbor,power)
	assert(false,"No shortest decimal for finite binary64")
	return "null"
