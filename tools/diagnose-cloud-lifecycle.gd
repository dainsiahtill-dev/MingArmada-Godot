extends SceneTree
const Weather=preload("res://modules/environment_engine/weather_state.gd")
var output:="res://Temp/cloud-lifecycle-baseline.json"
func _initialize()->void:run.call_deferred()
func run()->void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--output="):output=a.trim_prefix("--output=")
	var w:=Weather.new();w.configure({"epoch":1,"model_scale":10.0})
	var prior:Dictionary=w.snapshot();var resets:Array=[];var samples:Array=[]
	for tick in range(1,1921):
		var p:Dictionary=w.advance(tick/32.0,{},{})
		for i in 3:
			var a:Array=prior.worldClouds[i].worldPosition;var b:Array=p.worldClouds[i].worldPosition
			var jump:=Vector3(b[0]-a[0],b[1]-a[1],b[2]-a[2]).length()
			if jump>100:resets.append({"index":i,"time":p.acceptedTime,"from":a,"to":b,"jump_m":jump})
		if tick%32==0:
			var states:Array=w._compiler.render_states(w._weather_graphs[0],p.acceptedTime,{},true,{},false,false,true)
			var alpha:=0.0;var opaque:=0
			for s:Dictionary in states:
				if s.texture in ["cloud_sh.dds","stormshadow.dds"]:continue
				alpha+=float(s.alpha);opaque+=int(float(s.alpha)>0.0)
			samples.append({"time":p.acceptedTime,"position":p.worldClouds[0].worldPosition,"alpha_sum":alpha,"positive_parts":opaque,"rng":p.source.rngState})
		prior=p
	var f:=FileAccess.open(output,FileAccess.WRITE);f.store_string(JSON.stringify({"resets":resets,"samples":samples,"sources":{"weather":FileAccess.get_sha256("res://modules/environment_engine/weather_state.gd")}},"\t"));f.close()
	print("CLOUD_LIFECYCLE_DIAGNOSIS resets=",resets.size()," samples=",samples.size());quit()
