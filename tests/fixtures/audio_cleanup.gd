extends RefCounted
## AudioServer releases stopped playback on its mix thread, independently of
## SceneTree frame count. Test shutdown waits for actual release, with a bound.
static func stop_players(owner: Node) -> Array[WeakRef]:
	var playbacks: Array[WeakRef]=[]
	for player: AudioStreamPlayer in owner.find_children("*","AudioStreamPlayer",true,false):
		if player.has_stream_playback(): playbacks.append(weakref(player.get_stream_playback()))
		# stop() deliberately does not emit finished. A released playback weakref
		# confirms that the audio thread has consumed stop and removed ownership.
		player.stream_paused=false; player.stop(); player.stream=null
	return playbacks

static func wait_for_release(tree: SceneTree,playbacks: Array[WeakRef],timeout_ms: int = 250) -> bool:
	var deadline:=Time.get_ticks_msec()+timeout_ms
	while playbacks.any(func(playback: WeakRef): return playback.get_ref()!=null):
		if Time.get_ticks_msec()>=deadline: return false
		# Yield both SceneTree and the mix thread; finish as soon as ownership ends.
		await tree.create_timer(0.001).timeout
	return true
