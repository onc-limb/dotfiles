#!/bin/bash

set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create symlink with backup
create_link() {
    local src="$1"
    local dest="$2"

    # Create parent directory if it doesn't exist
    mkdir -p "$(dirname "$dest")"

    if [ -L "$dest" ]; then
        # Already a symlink
        if [ "$(readlink "$dest")" = "$src" ]; then
            info "Already linked: $dest"
            return 0
        else
            warn "Removing existing symlink: $dest"
            rm "$dest"
        fi
    elif [ -e "$dest" ]; then
        # File or directory exists, backup it
        local backup="${dest}.backup.$(date +%Y%m%d%H%M%S)"
        warn "Backing up existing file: $dest -> $backup"
        mv "$dest" "$backup"
    fi

    ln -s "$src" "$dest"
    info "Linked: $src -> $dest"
}

main() {
    echo "========================================"
    echo "  Dotfiles Installation Script"
    echo "========================================"
    echo ""

    # ~/.config directory links
    create_link "$DOTFILES_DIR/aerospace" "$HOME/.config/aerospace"
    create_link "$DOTFILES_DIR/borders" "$HOME/.config/borders"
    create_link "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"
    create_link "$DOTFILES_DIR/wezterm" "$HOME/.config/wezterm"
    create_link "$DOTFILES_DIR/starship.toml" "$HOME/.config/starship.toml"

    echo ""
    echo "========================================"
    echo "  Installation Complete!"
    echo "========================================"
}

main "$@"
