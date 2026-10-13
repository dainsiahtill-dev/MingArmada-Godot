extends RefCounted
## Finite-input 0x518790 translation. Its unusual collinear absolute-coordinate
## ratios are intentional; it is not a generic engine segment intersection API.
## Float stores match source locations. Godot operations are not x87 bit exact.
const EPSILON:=0.004999999888241291
static func _f32(value:float)->float:return PackedFloat32Array([value])[0]
static func _divide(a:float,b:float)->float:
	if b!=0.0:return a/b
	if a==0.0:return NAN
	return INF if a>0.0 else -INF
static func intersect(a:Vector2,b:Vector2,c:Vector2,d:Vector2,initial:Vector2=Vector2(23.25,-91.5))->Dictionary:
	if not a.is_finite() or not b.is_finite() or not c.is_finite() or not d.is_finite():
		return {"hit":false,"point":initial,"wrote":false,"branch":"nonfinite target rejection"}
	var abx:=_f32(float(b.x)-a.x);var aby:=_f32(float(b.y)-a.y)
	var cdx:=_f32(float(d.x)-c.x);var cdy:=_f32(float(d.y)-c.y)
	var determinant:=_f32(cdy*abx-cdx*aby)
	var acy:=float(a.y)-c.y;var acx:=float(a.x)-c.x
	var numerator_a:=_f32(acy*cdx-acx*cdy)
	var numerator_c:=_f32(acy*abx-acx*aby)
	var nonparallel:=determinant-EPSILON>=0.0 or determinant+EPSILON<=0.0
	if nonparallel:
		var reciprocal:=1.0/determinant;var reciprocal_store:=_f32(reciprocal)
		var t:=reciprocal*numerator_a;var t_store:=_f32(t)
		if t>=0.0 and t<=1.0:
			var u:=reciprocal_store*numerator_c
			if u>=0.0 and u<=1.0:return {"hit":true,"point":Vector2(_f32(t_store*abx+a.x),_f32(t_store*aby+a.y)),"wrote":true,"branch":"nonparallel-hit"}
	if nonparallel or numerator_a-EPSILON>=0.0 or numerator_a+EPSILON<=0.0 or numerator_c-EPSILON>=0.0 or numerator_c+EPSILON<=0.0:
		return {"hit":false,"point":initial,"wrote":false,"branch":"noncollinear-or-outside"}
	var reciprocal_x:=_divide(1.0,cdx);var reciprocal_y:=_divide(1.0,cdy)
	var b_x_store:=_f32(float(b.x)*reciprocal_x)
	var reciprocal_y_store:=_f32(reciprocal_y);var b_y:=reciprocal_y*float(b.y)
	if b_y>b_x_store-EPSILON and b_y<b_x_store+EPSILON and b_x_store>=0.0 and b_x_store<=1.0:
		return {"hit":true,"point":b,"wrote":true,"branch":"collinear-B-hit"}
	var a_x_store:=_f32(reciprocal_x*float(a.x));var a_y:=reciprocal_y_store*float(a.y)
	if a_y>a_x_store-EPSILON and a_y<a_x_store+EPSILON and a_x_store>=0.0 and a_x_store<=1.0:
		return {"hit":false,"point":a,"wrote":true,"branch":"collinear-A-written-AL-zero"}
	return {"hit":false,"point":initial,"wrote":false,"branch":"collinear-no-hit"}
