extends Node
## Assets — runtime loader for room/scene art (autoload).
##
## The sequels ship art-light: plates land in assets/backgrounds_hd/<bg>.png as
## they're made, and anything missing degrades gracefully (returns null) so the
## whole game is playable as a scaffold before a single plate exists.

const HD_BG_DIR := "res://assets/backgrounds_hd/"

var _tex_cache: Dictionary = {}      # path -> Texture2D (or null sentinel)

## Load a texture by res:// path. Prefers the imported resource (works inside an
## exported .pck) and falls back to a raw disk load (running from source).
func load_texture(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		var res = ResourceLoader.load(path)
		if res is Texture2D:
			tex = res
	if tex == null and FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(path) == OK:
			tex = ImageTexture.create_from_image(img)
	_tex_cache[path] = tex
	return tex

## Background plate for a room's bg id, or null if not yet painted.
func background(bg_id: String) -> Texture2D:
	if bg_id == "":
		return null
	return load_texture(HD_BG_DIR + bg_id + ".png")
