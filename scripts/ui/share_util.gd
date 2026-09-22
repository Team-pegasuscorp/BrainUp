class_name ShareUtil
extends RefCounted

## Opens the system share sheet with an image and a text. Android goes through
## the FileProvider shipped in Godot's template (<package>.fileprovider, which
## exposes the app's files dir, i.e. user://). Elsewhere, or if anything fails,
## the text is copied to the clipboard and the image stays saved in user://.

const SHARE_PATH := "user://share/brainup_result.png"

enum Result { SHARED, COPIED }


static func share(image: Image, text: String) -> int:
	var saved := false
	if image != null and not image.is_empty():
		DirAccess.make_dir_recursive_absolute(SHARE_PATH.get_base_dir())
		saved = image.save_png(SHARE_PATH) == OK
	if OS.get_name() == "Android" and _share_android(SHARE_PATH if saved else "", text):
		return Result.SHARED
	DisplayServer.clipboard_set(text)
	return Result.COPIED


static func _share_android(path: String, text: String) -> bool:
	if not Engine.has_singleton("AndroidRuntime"):
		return false
	var activity = Engine.get_singleton("AndroidRuntime").getActivity()
	var intent_class := JavaClassWrapper.wrap("android.content.Intent")
	if activity == null or intent_class == null:
		return false

	var intent = intent_class.Intent("android.intent.action.SEND")
	if intent == null:
		return false
	intent.putExtra("android.intent.extra.TEXT", text)
	intent.setType("text/plain")

	if not path.is_empty():
		var file = JavaClassWrapper.wrap("java.io.File").File(ProjectSettings.globalize_path(path))
		var provider := JavaClassWrapper.wrap("androidx.core.content.FileProvider")
		var uri = provider.getUriForFile(activity, str(activity.getPackageName()) + ".fileprovider", file) if provider != null and file != null else null
		if uri != null:
			intent.putExtra("android.intent.extra.STREAM", uri)
			intent.setType("image/png")
			## FLAG_GRANT_READ_URI_PERMISSION: lets the receiving app read the file.
			intent.addFlags(1)
			## Recent Android versions grant access (and show a preview) through ClipData.
			var clip_class := JavaClassWrapper.wrap("android.content.ClipData")
			if clip_class != null:
				var clip = clip_class.newRawUri("BrainUp", uri)
				if clip != null:
					intent.setClipData(clip)

	var chooser = intent_class.createChooser(intent, TranslationServer.translate("UI_SHARE"))
	activity.startActivity(chooser if chooser != null else intent)
	return JavaClassWrapper.get_exception() == null
