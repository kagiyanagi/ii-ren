#!/usr/bin/env bash

# Command: iiren save
# The reverse of an install: pulls the settings you edit outside the repo -
# through the Settings GUI and in ~/.config/hypr/custom - back into dots/, so
# `git diff` shows what you changed and you can commit it.
echo -e "${BLUE}Saving live settings into the repo...${NC}"

REPO="${BASE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
CHANGED=0

save_file() {
    local src="$1" dest="$2"
    [ -f "$src" ] || return 0
    mkdir -p "$(dirname "$dest")"
    if cmp -s "$src" "$dest"; then return 0; fi
    cp "$src" "$dest"
    echo -e "${GREEN}  ✓ ${dest#"$REPO"/}${NC}"
    CHANGED=$((CHANGED + 1))
}

save_file "$HOME/.config/illogical-impulse/config.json" \
          "$REPO/dots/.config/illogical-impulse/config.json"

for f in "$HOME"/.config/hypr/custom/*.lua; do
    [ -e "$f" ] || continue
    save_file "$f" "$REPO/dots/.config/hypr/custom/$(basename "$f")"
done

if [ "$CHANGED" -eq 0 ]; then
    echo -e "${GREEN}✓ Nothing changed - the repo already matches your live setup.${NC}"
else
    echo ""
    echo -e "${GREEN}✓ $CHANGED file(s) updated. Review and commit:${NC}"
    echo -e "${BLUE}    cd $REPO && git diff${NC}"
fi
