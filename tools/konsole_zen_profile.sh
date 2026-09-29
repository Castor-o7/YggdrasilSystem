#!/bin/sh
# Linux counterpart of terminal_zen_profile.sh: make the "Yggdrasil"
# Konsole profile the cockpit switches every session to in zen. It is the
# user's default profile with a copy of its colour scheme whose
# background is fully transparent (Opacity=0) and unblurred, so the text
# sits on the void. Both files go in ~/.local/share/konsole; nothing else
# of the user's is touched. A Konsole reads its profile directory only
# when it starts: one already running when this first makes the profile
# cannot switch to it until it is restarted (Konsole 26.08).
set -e
cd "$(dirname "$0")/.."
[ "$(uname)" = "Linux" ] || { echo "konsole_zen_profile.sh: Linux only (macOS: terminal_zen_profile.sh)" >&2; exit 1; }
mkdir -p terminal

ZEN=Yggdrasil
data=${XDG_DATA_HOME:-$HOME/.local/share}
out="$data/konsole"
mkdir -p "$out"

# The first konsole/<file> along the XDG data dirs, user's first.
find_data() {
	old_ifs=$IFS
	IFS=:
	for d in "$data" ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
		if [ -f "$d/konsole/$1" ]; then
			IFS=$old_ifs
			echo "$d/konsole/$1"
			return 0
		fi
	done
	IFS=$old_ifs
	return 1
}

# One key of an INI file, without KConfig's cascade (the file is absolute).
ini() {
	kreadconfig6 --file "$1" --group "$2" --key "$3" 2>/dev/null || true
}

# The source: Konsole's default profile, unless that is already the zen
# profile (a crash mid-zen), in which case the one recorded last time.
src_file=$(kreadconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile 2>/dev/null || true)
if [ "$src_file" = "$ZEN.profile" ] || [ -z "$src_file" ]; then
	src_file=""
	if [ -s terminal/.source ]; then
		src_file="$(cat terminal/.source).profile"
	fi
fi
src_path=""
[ -n "$src_file" ] && src_path=$(find_data "$src_file" || true)

if [ -n "$src_path" ]; then
	src_name=$(ini "$src_path" General Name)
	[ -n "$src_name" ] || src_name=$(basename "$src_path" .profile)
	scheme=$(ini "$src_path" Appearance ColorScheme)
	cp "$src_path" "$out/$ZEN.profile"
else
	# No profile file: Konsole is on its built-in profile.
	src_name="Built-in"
	scheme=""
	printf '[General]\nParent=FALLBACK/\n' > "$out/$ZEN.profile"
fi
[ -n "$scheme" ] || scheme=Breeze
# Remember which profile the zen profile is built from, so the cockpit can
# hand Konsole back to it even if its own memory of it is lost.
[ "$src_name" = "$ZEN" ] || echo "$src_name" > terminal/.source

kwriteconfig6 --file "$out/$ZEN.profile" --group General --key Name "$ZEN"
kwriteconfig6 --file "$out/$ZEN.profile" --group Appearance --key ColorScheme "$ZEN"
# No scrollbar in zen: nothing but the text on the void (2 = hidden).
kwriteconfig6 --file "$out/$ZEN.profile" --group Scrolling --key ScrollBarPosition 2

scheme_path=$(find_data "$scheme.colorscheme" || true)
if [ -n "$scheme_path" ] && [ "$scheme" != "$ZEN" ]; then
	cp "$scheme_path" "$out/$ZEN.colorscheme"
else
	# Breeze is compiled into Konsole, with no file to copy: its two
	# ground colours are enough, the palette falls back to Konsole's own.
	printf '[Background]\nColor=35,38,39\n\n[Foreground]\nColor=252,252,252\n' > "$out/$ZEN.colorscheme"
fi
kwriteconfig6 --file "$out/$ZEN.colorscheme" --group General --key Description "$ZEN"
kwriteconfig6 --file "$out/$ZEN.colorscheme" --group General --key Opacity 0
kwriteconfig6 --file "$out/$ZEN.colorscheme" --group General --key Blur false
echo "$out/$ZEN.profile (from $src_name, scheme $scheme)"
