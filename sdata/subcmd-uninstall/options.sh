# Handle args for subcmd: uninstall
# shellcheck shell=bash

showhelp(){
echo -e "Syntax: $0 uninstall [OPTIONS]...

Unintall dots.

Options:
  -h, --help       Show this help message
"
}
# `man getopt` to see more
para=$(getopt \
  -o h \
  -l help \
  -n "$0" -- "$@")
[ $? != 0 ] && echo "$0: Error when getopt, please recheck parameters." && exit 1
#####################################################################################
# -h/--help is the only option, and it is honoured regardless of position.
showhelp_if_asked "$para"
