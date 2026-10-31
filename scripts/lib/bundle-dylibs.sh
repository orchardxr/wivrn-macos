# Copies the Homebrew / /usr/local dylibs that binaries link (recursively) into one directory and points the
# binaries at @rpath, so the app runs without Homebrew or the Vulkan SDK. Source from bash.
#   bundle_dylibs <lib dir> <binary>...
# Binaries linking a bundled lib get an LC_RPATH to <lib dir>. Safe to run over files that are already bundled (by
# macdeployqt or an earlier call): it then only fixes the references still pointing outside.

_bundle_resolve() { # <dep> <dir of the file that links it>
	local dep="$1" dir="$2" n="${1##*/}" c
	case "$dep" in
		/opt/homebrew/* | /usr/local/*) if [[ -e "$dep" ]]; then echo "$dep"; fi ;;
		*.framework/*) ;;
		@loader_path/* | @rpath/*)
			for c in "$dir/${dep#*/}" "/opt/homebrew/lib/$n" "/usr/local/lib/$n" /opt/homebrew/opt/*/lib/"$n" \
				/usr/local/opt/*/lib/"$n"; do
				if [[ -e "$c" ]]; then
					echo "$c"
					return
				fi
			done ;;
	esac
}

_bundle_relpath() { # <from dir> <to dir>
	local from="$1" to="$2" up="" rest
	while [[ "$to/" != "$from/"* ]]; do
		from="${from%/*}"
		up="../$up"
	done
	rest="${to#"$from"}"
	rest="${up}${rest#/}"
	echo "${rest%/}"
}

_bundle_rpath() { # <file> <lib dir>
	local rel
	rel="$(_bundle_relpath "$(dirname "$(realpath "$1")")" "$(realpath "$2")")"
	rel="@loader_path${rel:+/$rel}"
	otool -l "$1" | grep -q "path $rel " || install_name_tool -add_rpath "$rel" "$1" 2>/dev/null
}

bundle_dylibs() {
	local lib="$1" f origin dep src name entry self r
	shift
	mkdir -p "$lib"
	local queue=()
	for f in "$@"; do queue+=("$f|$(dirname "$f")"); done
	while ((${#queue[@]})); do
		entry="${queue[0]}"
		queue=("${queue[@]:1}")
		f="${entry%%|*}" origin="${entry#*|}"
		self="$(otool -D "$f" | sed -n 2p)"
		case "$self" in
			/opt/homebrew/*.framework/* | /usr/local/*.framework/*)
				install_name_tool -id "@rpath/$(sed 's|.*/\([^/]*\.framework/\)|\1|' <<< "$self")" "$f" 2>/dev/null ;;
			/opt/homebrew/* | /usr/local/*) install_name_tool -id "@rpath/${self##*/}" "$f" 2>/dev/null ;;
		esac
		# Absolute rpaths (Homebrew, the build tree) would make dyld prefer those copies on Macs that have them.
		for r in $(otool -l "$f" | awk '/LC_RPATH/ { r = 1 } r && $1 == "path" { print $2; r = 0 }'); do
			[[ "$r" == @* ]] || install_name_tool -delete_rpath "$r" "$f" 2>/dev/null
		done
		for dep in $(otool -L "$f" | tail -n +2 | awk '{print $1}'); do
			[[ "$dep" == "$self" ]] && continue
			name="${dep##*/}"
			[[ -e "$(dirname "$f")/$name" && "$(dirname "$f")" != "$lib" ]] && continue
			src="$(_bundle_resolve "$dep" "$origin")"
			[[ -n "$src" ]] || continue
			if [[ ! -e "$lib/$name" ]]; then
				cp -L "$src" "$lib/$name"
				chmod u+w "$lib/$name"
				install_name_tool -id "@rpath/$name" "$lib/$name" 2>/dev/null
				queue+=("$lib/$name|$(dirname "$(realpath "$src")")")
			fi
			[[ "$dep" == "@rpath/$name" ]] || install_name_tool -change "$dep" "@rpath/$name" "$f" 2>/dev/null
		done
		if otool -L "$f" | tail -n +2 | awk -v s="$self" '$1 != s && $1 ~ /^@rpath\//' | grep -q .; then
			_bundle_rpath "$f" "$lib"
		fi
	done
}
