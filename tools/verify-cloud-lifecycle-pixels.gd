extends SceneTree
var failures:Array[String]=[]
var output:="res://docs/research/evidence/world-cloud-lifecycle-2026-10-15"
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL cloud pixels: ",message)
func compare(baseline:Image,candidate:Image,roi:Rect2i)->Dictionary:
	var count:=0;var sum:=Vector2.ZERO
	for y in range(roi.position.y,roi.end.y):
		for x in range(roi.position.x,roi.end.x):
			var a:=baseline.get_pixel(x,y);var b:=candidate.get_pixel(x,y)
			# The source storm is dark; isolate its survival against unchanged sky
			# and sea, instead of counting unrelated brighter wave differences.
			if (a.r-b.r)+(a.g-b.g)+(a.b-b.b)>.09:
				count+=1;sum+=Vector2(x,y)
	return {"pixels":count,"centroid":[sum.x/maxi(1,count),sum.y/maxi(1,count)]}
func _initialize()->void:
	var rows:Array=[]
	var prior:Dictionary={}
	for tick in [2,8,15,30,60,90,120]:
		var row:Dictionary={"accepted_time":tick/60.0}
		for view:String in ["main","mirror"]:
			var suffix:="-mirror" if view=="mirror" else ""
			var left:="%s/production-2/baseline-%03d%s.png"%[output,tick,suffix]
			var right:="%s/production-2/production-%03d%s.png"%[output,tick,suffix]
			var a:=Image.load_from_file(left);var b:=Image.load_from_file(right)
			check(a!=null and b!=null,"read frozen images")
			if a==null or b==null:continue
			var roi:=Rect2i(150,250,900,240) if view=="main" else Rect2i(80,230,550,210)
			row[view]=compare(a,b,roi)
			check(row[view].pixels>(1000 if view=="main" else 300),"cloud survives reset in actual "+view+" pixels tick="+str(tick))
			if prior.has(view):
				var ca:=Vector2(row[view].centroid[0],row[view].centroid[1]);var cb:=Vector2(prior[view].centroid[0],prior[view].centroid[1])
				check(ca.distance_to(cb)<90.0,"continuous visible cloud centroid "+view)
		rows.append(row);prior=row
	check(float(rows[-1].main.centroid[0])<float(rows[0].main.centroid[0])-100.0,"retained cloud visibly travels rather than freezing")
	var file:=FileAccess.open(output+"/PIXEL_VERIFY.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"valid":failures.is_empty(),"failures":failures,"rows":rows,"scope":"Signed darkening against paired source-identical baseline frames isolates the retained storm cloud. Main and raw planar-reflection framebuffer, fixed camera, seven accepted times0.033..2s. Centroid continuity is sampled, not proof for every possible camera or whole-game FPS."},"\t"));file.close()
	print("CLOUD_LIFECYCLE_PIXEL_TESTS frames=",rows.size()*2," failures=",failures.size());quit(1 if failures.size() else 0)
