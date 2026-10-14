extends "res://tools/diagnose-voyage-ship-line.gd"
## Shared instrumented candidate injection. Read-back occurs on the render thread.
var _diagnostic_ready:=false
var _diagnostic:Dictionary={}
func _make_backend()->RefCounted:return null
func _receive_diagnostic(receipt:Dictionary)->void:
	_diagnostic=receipt;_diagnostic_ready=true
func capture(scene:Control,label:String)->void:
	var effect:CompositorEffect=scene.sea.source_shadows._effect
	if label=="all-retained" and effect:
		RenderingServer.call_on_render_thread(func():
			if effect._backend:effect._backend.dispose()
			var candidate:RefCounted=_make_backend()
			if candidate:
				candidate.initialize(RenderingServer.get_rendering_device());effect._backend=candidate)
		await frames(4)
	await super.capture(scene,label)
	_diagnostic_ready=false
	if effect:
		RenderingServer.call_on_render_thread(func():
			var active:RefCounted=effect._backend
			var receipt:Dictionary={"present":active!=null,"effectEnabled":effect.enabled}
			if active:
				receipt.backendId=active.get_instance_id();receipt.script=active.get_script().resource_path
				receipt.drawCount=active.draw_count;receipt.uploadCount=active.upload_count;receipt.cachedMeshes=active.cached_mesh_count();receipt.error=active.last_error
				if active.has_method("candidate_diagnostics"):receipt.candidate=active.candidate_diagnostics()
				receipt.make_read_only()
			_receive_diagnostic.call_deferred(receipt))
		for wait in 120:
			await process_frame
			if _diagnostic_ready:break
	if not captures.is_empty():captures[-1].candidateReadback=_diagnostic if _diagnostic_ready else {"error":"render-thread-diagnostic-timeout"}
