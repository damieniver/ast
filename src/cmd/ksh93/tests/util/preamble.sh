#
# Setup the environment for the unit test.
#
readonly test_file=${0##*/}
readonly test_name=$1

#
# Ensure we use ksh builtins where traditionally an external command would be used. This helps
# ensure that a) our builtins get tested even if only indirectly, and b) our unit tests can rely
# on predictable behavior from external commands that may have different behavior on different
# platforms. A few tests need to use external variants of builtins so find them first.
#
bin_basename=$(whence -p basename)
bin_cat=$(whence -p cat)
bin_chmod=$(whence -p chmod)
bin_cmp=$(whence -p cmp)
bin_date=$(whence -p date)
bin_echo=$(whence -p echo)
bin_false=$(whence -p false)
bin_printf=$(whence -p printf)
bin_rm=$(whence -p rm)
bin_sleep=$(whence -p sleep)
bin_tee=$(whence -p tee)
bin_true=$(whence -p true)
bin_uname=$(whence -p uname)

# We have tests that should only run if the `nc` (netcat) command is available.
whence -q nc && readonly nc_available=yes || readonly nc_available=no

# There are at least two tests that are broken if all builtins are enabled by munging PATH.
# So make it easy for a unit test to not enable all builtins by default. See issue #960.
NO_BUILTINS_PATH=$PATH
PATH=/opt/ast/bin:$PATH
FULL_PATH=$PATH

#
# Make sure the unit test can't inadvertantly modify several critical env vars.
#
readonly NO_BUILTINS_PATH
readonly FULL_PATH
readonly OLD_PATH
readonly SAFE_PATH
readonly TEST_DIR
readonly TEST_SRC_DIR
readonly BUILD_DIR
readonly OS_NAME

#
# Create some functions for reporting and counting errors.
#
integer error_count=0
integer start_of_test_lineno=0  # redefined later to be read-only

function log_info {
    typeset lineno=$(( $1 < 0 ? $1 : $1 - $start_of_test_lineno ))
    print -r "<I> ${test_name}[$lineno]: ${@:2}"
}
alias log_info='log_info $LINENO'

function log_warning {
    typeset lineno=$(( $1 < 0 ? $1 : $1 - $start_of_test_lineno ))
    print -u2 -r "<W> ${test_name}[$lineno]: ${@:2}"
}
alias log_warning='log_warning $LINENO'

function log_error {
    typeset lineno=$(( $1 < 0 ? $1 : $1 - $start_of_test_lineno ))
    typeset msg="$2"
    print -u2 -r "<E> ${test_name}[$lineno]: $msg"
    if (( $# > 2 ))
    then
        print -u2 -r "<E> expect: |$3|"
        print -u2 -r "<E> actual: |$4|"
    fi
    (( error_count++ ))
}
alias log_error='log_error $LINENO'

#
# Open a couple of named pipes (fifos) for the unit test to use as barriers rather than using
# arbitrary sleeps. The fifos are created by the run_test.sh script which sets up our environment.
#
exec 9<>fifo9
exec 8<>fifo8
function empty_fifos {
    typeset _x
    read -u9 -t0.01 _x && {
        'log_warning' $1 "fifo9 unexpectedly had data: '$_x'"
    }
    read -u8 -t0.01 _x && {
        'log_warning' $1 "fifo9 unexpectedly had data: '$_x'"
    }
}
alias empty_fifos='empty_fifos $LINENO'

#
# Verify that /dev/fd is functional. Note that on some systems (e.g., FreeBSD) there is a stub
# /dev/fd that only supports 0, 1, and 2. On such systems a special pseudo-filesystem may need to
# be mounted or a custom kernel built to get full /dev/fd support.
#
# Note that we can't do the straightforward `[[ -p /dev/fd/8 ]]` because such paths are
# special-cased by ksh and work even if the system doesn't support /dev/fd. But there may be tests
# where we need to know if those paths are recognized by the OS.
#
HAS_DEV_FD=no
[[ $(print /dev/fd/*) == *' /dev/fd/8 '* ]] && HAS_DEV_FD=yes
readonly HAS_DEV_FD

#
# Platforms like OpenBSD have `jot` instead of `seq`. For the simple case of emitting ints from one
# to n they are equivalent. And that should be the only use of `seq` in unit tests.
#
whence -q seq || alias seq=jot

#
# Capture the current line number so we can calculate the correct line number in the unit test file
# that will be appended to this preamble script. This must be the last line in this preamble script.
#
# Note: It is tempting to just do `LINENO=1` and avoid introducing a global var. Doing so, however,
# breaks at least two unit tests. Whether that breakage indicates bugs in ksh or the unit test is
# unknown.
#
typeset -ri start_of_test_lineno=$LINENO
