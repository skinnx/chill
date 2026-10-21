class_name AtomicFile
extends RefCounted
## Crash-safe text files (synthesis D12, 01 §7): write <path>.tmp, verify it, keep the previous
## file as <path>.bak, then rename the temp file into place. A crash at any point leaves at least
## one complete file among <path>, <path>.tmp and <path>.bak.

const TMP_SUFFIX := ".tmp"
const BAK_SUFFIX := ".bak"


## Writes [param text] to [param path] atomically. [param verify] (optional) receives the text read
## back from the temp file and must return true for the swap to happen.
static func write_text(path: String, text: String, keep_backup: bool = true, verify: Callable = Callable()) -> Error:
	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var mk := DirAccess.make_dir_recursive_absolute(dir_path)
		if mk != OK:
			return mk
	var tmp := path + TMP_SUFFIX
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	if not f.store_string(text):
		f.close()
		return ERR_FILE_CANT_WRITE
	f.flush()
	var werr := f.get_error()
	f.close()
	if werr != OK:
		return werr
	if verify.is_valid():
		var back := FileAccess.get_file_as_string(tmp)
		var ok: bool = verify.call(back)
		if not ok:
			return ERR_FILE_CORRUPT
	if FileAccess.file_exists(path):
		if keep_backup:
			var bak := path + BAK_SUFFIX
			if FileAccess.file_exists(bak):
				DirAccess.remove_absolute(bak)
			var rb := DirAccess.rename_absolute(path, bak)
			if rb != OK:
				return rb
		else:
			DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path)


## Candidate files to read, newest first: the file, an orphaned temp file, the backup.
static func candidates(path: String) -> PackedStringArray:
	return PackedStringArray([path, path + TMP_SUFFIX, path + BAK_SUFFIX])


static func read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


static func remove_all(path: String) -> void:
	for p: String in candidates(path):
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
