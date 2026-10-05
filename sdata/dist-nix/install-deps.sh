# This script is meant to be sourced.
# It's not for directly running.

function vianix-warning(){
  printf "${STY_YELLOW}"
  printf "Currently \"--via-nix\" will run:\n"
  printf "  home-manager switch --flake .#illogical_impulse\n"
  printf "If you are already using home-manager,\n"
  printf "it may override your current config,\n"
  printf "despite that this should be reversible.\n"
  printf "${STY_RST}"
  pause
}
function install_nix(){
  # https://github.com/NixOS/experimental-nix-installer
  local cmd=nix

  x mkdir -p ${REPO_ROOT}/cache
  x curl -JLo ${REPO_ROOT}/cache/nix-installer https://artifacts.nixos.org/experimental-installer
  # -f promises no prompts; the installer also refuses to ask without a terminal
  x sh ${REPO_ROOT}/cache/nix-installer install $($ask || echo --no-confirm)
  try source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'

  command -v $cmd && return
  echo "Failed in installing $cmd."
  echo "Please install it by yourself and then retry."
  return 1
}
function install_home-manager(){
  # https://nix-community.github.io/home-manager/index.xhtml#sec-install-standalone
  local cmd=home-manager
  # Maybe installed already, just not sourced yet
  try source $HOME/.nix-profile/etc/profile.d/hm-session-vars.sh
  command -v $cmd && return

  # Same branches as home-manager/flake.nix: Hyprland 0.56 is only on unstable.
  x nix-channel --add https://nixos.org/channels/nixos-unstable nixpkgs-home
  x nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
  x nix-channel --update
  x env NIX_PATH="nixpkgs=$HOME/.nix-defexpr/channels/nixpkgs-home" nix-shell '<home-manager>' -A install

  command -v $cmd && return
  echo "Failed in installing $cmd."
  echo "Please install it by yourself and then retry."
  echo ""
  echo "Hint: It's also possible that the installation is actually successful,"
  echo "but your \"\$PATH\" is not properly set."
  echo "This can happen when you have used \"su user\" to switch user."
  echo "If this is the problem, use \"su - user\" instead."
  return 1
}
function hm_deps(){
  SETUP_HM_DIR="${REPO_ROOT}/sdata/dist-nix/home-manager"
  SETUP_USERNAME_NIXFILE="${SETUP_HM_DIR}/username.nix"
  echo "\"$(whoami)\"" > "${SETUP_USERNAME_NIXFILE}"
  x git add "${SETUP_USERNAME_NIXFILE}"
  cd $SETUP_HM_DIR
  x home-manager switch --flake .#illogical_impulse \
    --extra-experimental-features nix-command \
    --extra-experimental-features flakes
  # NixOS provides the GPU drivers itself; the helper is for every other distro.
  [ -e /etc/NIXOS ] || x sudo /nix/store/*-non-nixos-gpu/bin/non-nixos-gpu-setup
  cd $REPO_ROOT
  x git rm -f "${SETUP_USERNAME_NIXFILE}"
}

function nixos-preflight(){
  # Home Manager can't set these: they are NixOS options. Without nix-ld the venv
  # step fails (uv's Python and the pip wheels are generic Linux binaries; NixOS
  # only has a stub loader), and without the graphics drivers Hyprland can't start.
  local missing=()
  readlink /lib64/ld-linux-x86-64.so.2 2>/dev/null | grep -q nix-ld || missing+=("programs.nix-ld.enable = true;")
  [ -e /run/opengl-driver ] || missing+=("hardware.graphics.enable = true;")
  printf "${STY_CYAN}NixOS: also worth having in configuration.nix, for the parts Home Manager can't do:\n"
  printf "  programs.fish.enable = true; services.gnome.gnome-keyring.enable = true;\n"
  printf "  hardware.bluetooth.enable = true; programs.ydotool.enable = true;\n"
  printf "Display managers don't list Home Manager's Hyprland: start it from a TTY, or with greetd\n"
  printf "running ~/.nix-profile/bin/Hyprland.${STY_RST}\n"
  [ ${#missing[@]} -eq 0 ] && return
  printf "${STY_RED}Add to /etc/nixos/configuration.nix, run \"sudo nixos-rebuild switch\", then run this again:\n"
  printf "  %s\n" "${missing[@]}"
  printf "${STY_RST}"
  exit 1
}

##################################################
##################################################

[ -e /etc/NIXOS ] && nixos-preflight
vianix-warning

TEST_CMDS=(curl fish swaylock gnome-keyring)
ensure_cmds "${TEST_CMDS[@]}"

if ! command -v nix >/dev/null 2>&1;then
  echo -e "${STY_YELLOW}[$0]: \"nix\" not found.${STY_RST}"
  showfun install_nix
  v install_nix
fi
if ! command -v home-manager >/dev/null 2>&1;then
  echo -e "${STY_YELLOW}[$0]: \"home-manager\" not found.${STY_RST}"
  showfun install_home-manager
  v install_home-manager
fi

showfun hm_deps
v hm_deps
