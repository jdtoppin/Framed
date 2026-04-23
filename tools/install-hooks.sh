#!/bin/sh
# Install Framed's tracked git hooks into .git/hooks/ as symlinks.
# Re-run after cloning or after pulling new hook changes.

set -eu

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

install_hook() {
	name=$1
	src="tools/hooks/$name"
	dst=".git/hooks/$name"

	if [ ! -f "$src" ]; then
		echo "error: $src not found"
		exit 1
	fi

	chmod +x "$src"

	if [ -e "$dst" ] && [ ! -L "$dst" ]; then
		echo "warning: $dst exists and is not a symlink; backing up to $dst.bak"
		mv "$dst" "$dst.bak"
	fi

	ln -sf "../../$src" "$dst"
	echo "installed: $dst -> $src"
}

install_hook pre-commit
