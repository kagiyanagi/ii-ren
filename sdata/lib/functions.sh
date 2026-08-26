# This is NOT a script for execution, but for loading functions, so NOT need execution permission or shebang.
# NOTE that you NOT need to `cd ..' because the `$0' is NOT this file, but the script file which will source this file.

# shellcheck shell=bash

function try { "$@" || sleep 0; }
function v(){
  echo -e "####################################################"
  echo -e "${STY_BLUE}[$0]: Next command:${STY_RST}"
  echo -e "${STY_GREEN}$*${STY_RST}"
  local execute=true
  if $ask;then
    while true;do
      echo -e "${STY_BLUE}Execute? ${STY_RST}"
      echo "  y = Yes"
      echo "  e = Exit now"
      echo "  s = Skip this command (NOT recommended - your setup might not work correctly)"
      echo "  yesforall = Yes and don't ask again; NOT recommended unless you really sure"
      local p; read -p "====> " p
      case $p in
        [yY]) echo -e "${STY_BLUE}OK, executing...${STY_RST}" ;break ;;
        [eE]) echo -e "${STY_BLUE}Exiting...${STY_RST}" ;exit ;break ;;
        [sS]) echo -e "${STY_BLUE}Alright, skipping this one...${STY_RST}" ;execute=false ;break ;;
        "yesforall") echo -e "${STY_BLUE}Alright, won't ask again. Executing...${STY_RST}"; ask=false ;break ;;
        *) echo -e "${STY_RED}Please enter [y/e/s/yesforall].${STY_RST}";;
      esac
    done
  fi
  if $execute;then x "$@";else
    echo -e "${STY_YELLOW}[$0]: Skipped \"$*\"${STY_RST}"
  fi
}
# When use v() for a defined function, use x() INSIDE its definition to catch errors.
function x(){
  if "$@";then local cmdstatus=0;else local cmdstatus=1;fi # 0=normal; 1=failed; 2=failed but ignored
  while [ $cmdstatus == 1 ] ;do
    echo -e "${STY_RED}[$0]: Command \"${STY_GREEN}$*${STY_RED}\" has failed."
    echo -e "You may need to resolve the problem manually BEFORE repeating this command."
    echo -e "[Tip] If a certain package is failing to install, try installing it separately in another terminal.${STY_RST}"
    echo "  r = Repeat this command (DEFAULT)"
    echo "  e = Exit now"
    echo "  i = Ignore this error and continue (your setup might not work correctly)"
    local p; read -p " [R/e/i]: " p
    case $p in
      [iI]) echo -e "${STY_BLUE}Alright, ignore and continue...${STY_RST}";cmdstatus=2;;
      [eE]) echo -e "${STY_BLUE}Alright, will exit.${STY_RST}";break;;
      *) echo -e "${STY_BLUE}OK, repeating...${STY_RST}"
         if "$@";then cmdstatus=0;else cmdstatus=1;fi
         ;;
    esac
  done
  case $cmdstatus in
    0) echo -e "${STY_BLUE}[$0]: Command \"${STY_GREEN}$*${STY_BLUE}\" finished.${STY_RST}";;
    1) echo -e "${STY_RED}[$0]: Command \"${STY_GREEN}$*${STY_RED}\" has failed. Exiting...${STY_RST}";exit 1;;
    2) echo -e "${STY_RED}[$0]: Command \"${STY_GREEN}$*${STY_RED}\" has failed but ignored by user.${STY_RST}";;
  esac
}
function showfun(){
  echo -e "${STY_BLUE}[$0]: The definition of function \"$1\" is as follows:${STY_RST}"
  printf "${STY_GREEN}"
  type -a "$1" 2>/dev/null || return 1
  printf "${STY_RST}"
}
function pause(){
  if [ ! "$ask" == "false" ];then
    printf "${STY_FAINT}${STY_SLANT}"
    local p; read -p "(Ctrl-C to abort, Enter to proceed)" p
    printf "${STY_RST}"
  fi
}
function remove_bashcomments_emptylines(){
  echo "pwd=$(pwd)"
  echo "input=$1"
  echo "output=$2"
  mkdir -p "$(dirname "$2")"
  cat "$1" | sed -e 's/#.*//' -e '/^[[:space:]]*$/d' > "$2"
}
function prevent_sudo_or_root(){
  case $(whoami) in
    root) echo -e "${STY_RED}[$0]: This script is NOT to be executed with sudo or as root. Aborting...${STY_RST}";exit 1;;
  esac
}

# Initialize sudo session and keep it alive in background
# Store PID in a global variable that can be accessed by trap
declare -g SUDO_KEEPALIVE_PID=""

function sudo_init_keepalive(){
  # Check if sudo is available
  if ! command -v sudo >/dev/null 2>&1; then
    return 0
  fi

  # Skip if already initialized
  if [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
    return 0
  fi

  # Prompt for sudo password once at the beginning
  echo -e "${STY_CYAN}[$0]: Requesting sudo privileges for installation...${STY_RST}"
  if ! sudo true; then
    echo -e "${STY_RED}[$0]: Failed to obtain sudo privileges. Aborting...${STY_RST}"
    exit 1
  fi

  # Start background process to keep sudo session alive
  # This updates the sudo timestamp every 60 seconds
  (
    while true; do
      sleep 60
      sudo true 2>/dev/null || exit 0
    done
  ) &
  SUDO_KEEPALIVE_PID=$!

  echo -e "${STY_GREEN}[$0]: Sudo session initialized and will be kept alive (PID: $SUDO_KEEPALIVE_PID)${STY_RST}"
}

# Stop the sudo keepalive background process
function sudo_stop_keepalive(){
  if [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    SUDO_KEEPALIVE_PID=""
  fi
}
function git_auto_unshallow(){
# We need this function for latest_commit_hash to work properly
  if [[ -f "$(git rev-parse --git-dir)/shallow" ]]; then
    echo "Shallow clone detected. Unshallowing..."
    git fetch --unshallow
  fi
}
function latest_commit_timestamp(){
  local target_path="$1"
  local result=$(git log -1 --format="%ct" -- "$target_path" 2>/dev/null)
  if [[ -z "$result" ]]; then
    echo "[latest_commit_timestamp] The timestamp of \"$target_path\" is empty. Aborting..." >&2
    return 1
  fi
  echo "$result"
}

function log_info() {
  echo -e "${STY_BLUE}[INFO]${STY_RST} $1"
}
function log_success() {
  echo -e "${STY_GREEN}[SUCCESS]${STY_RST} $1"
}
function log_warning() {
  echo -e "${STY_YELLOW}[WARNING]${STY_RST} $1"
}
function log_error() {
  echo -e "${STY_RED}[ERROR]${STY_RST} $1" >&2
}
function log_header() {
  echo -e "\n${STY_PURPLE}=== $1 ===${STY_RST}"
}
function log_die() {
  log_error "$1"
  exit 1
}

# First pass over a getopt-normalized arg string: honour -h/--help wherever it
# appears, so help does not depend on option order. The caller's own loop then
# handles the remaining flags in order. Requires showhelp() to be defined.
function showhelp_if_asked(){
  local arg
  eval "set -- $1"
  for arg in "$@"; do
    case "$arg" in
      -h|--help) showhelp;exit;;
      --) return;;
    esac
  done
}

function auto_update_git_submodule(){
  if git submodule status --recursive | grep -E '^[+-U]';then
    # Note: `git pull --recurse-submodules` cannot substitute `git submodule update --init --recursive` cuz it does not init a submodule when needed.
    x git submodule update --init --recursive
  fi
}

function backup_clashing_targets(){
  # For non-recursive dirs/files under target_dir, only backup those which clashes with the ones under source_dir
  # However, ignore the ones listed in ignored_list

  # Deal with arguments
  local source_dir="$1"
  local target_dir="$2"
  local backup_dir="$3"
  local -a ignored_list=("${@:4}")

  # Find clash dirs/files, save as clash_list
  local clash_list=()
  local source_list=($(ls -A "$source_dir"))
  local target_list=($(ls -A "$target_dir"))
  local -A target_map
  for i in "${target_list[@]}"; do
    target_map["$i"]=1
  done
  for i in "${source_list[@]}"; do
    if [[ -n "${target_map[$i]}" ]]; then
      clash_list+=("$i")
    fi
  done
  local -A delk
  for del in "${ignored_list[@]}" ; do delk[$del]=1 ; done
  for k in "${!clash_list[@]}" ; do
    [ "${delk[${clash_list[$k]}]-}" ] && unset 'clash_list[k]'
  done
  clash_list=("${clash_list[@]}")

  # Construct args_includes for rsync
  local args_includes=()
  for i in "${clash_list[@]}"; do
    if [[ -d "$target_dir/$i" ]]; then
      args_includes+=(--include="/$i/")
      args_includes+=(--include="/$i/**")
    else
      args_includes+=(--include="/$i")
    fi
  done
  args_includes+=(--exclude='*')

  x mkdir -p $backup_dir
  x rsync -av --progress "${args_includes[@]}" "$target_dir/" "$backup_dir/"
}

function install_cmds(){
  case $OS_GROUP_ID in
    "arch")
      local pkgs=()
      for cmd in "$@";do
        # For package name which is not cmd name, use "case" syntax to replace
        case $cmd in
          ip) pkgs+=(iproute2);;
          *) pkgs+=($cmd) ;;
        esac
      done
      v sudo pacman -Syu
      v sudo pacman -S --noconfirm --needed "${pkgs[@]}"
      ;;
    "debian")
      local pkgs=()
      for cmd in "$@";do
        # For package name which is not cmd name, use "case" syntax to replace
        case $cmd in
          ip) pkgs+=(iproute2);;
          *) pkgs+=($cmd) ;;
        esac
      done
      v sudo apt update -y
      v sudo apt install -y "${pkgs[@]}"
      ;;
    "fedora")
      local pkgs=()
      for cmd in "$@";do
        # For package name which is not cmd name, use "case" syntax to replace
        case $cmd in
          ip) pkgs+=(iproute);;
          *) pkgs+=($cmd) ;;
        esac
      done
      v sudo dnf install -y "${pkgs[@]}"
      ;;
    "suse")
      local pkgs=()
      for cmd in "$@";do
        # For package name which is not cmd name, use "case" syntax to replace
        case $cmd in
          ip) pkgs+=(iproute2);;
          *) pkgs+=($cmd) ;;
        esac
      done
      v sudo zypper refresh
      v sudo zypper -n install "${pkgs[@]}"
      ;;
    *)
      printf "WARNING\n"
      printf "No method found to install package providing the commands:\n"
      printf "  $@\n"
      printf "Please install by yourself.\n"
      ;;
  esac
}

function ensure_cmds(){
  local not_found_cmds=()
  for cmd in "$@"; do
    if ! command -v $cmd >/dev/null 2>&1;then
      not_found_cmds+=($cmd)
    fi
  done
  if [[ ${#not_found_cmds[@]} -gt 0 ]]; then
    echo -e "${STY_YELLOW}[$0]: Not found: ${not_found_cmds[*]}.${STY_RST}"
    install_cmds "${not_found_cmds[@]}"
  fi
}

function dedup_and_sort_listfile(){
  if ! test -f "$1"; then
    echo "File not found: $1" >&2; return 2
  else
    temp="$(mktemp)"
    sort -u -- "$1" > "$temp"
    mv -f -- "$temp" "$2"
  fi
}
