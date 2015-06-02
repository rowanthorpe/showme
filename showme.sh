#!/bin/sh

# © Copyright 2015 Rowan Thorpe
#
# This file is part of Showme
#
# Showme is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Showme is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Showme. If not, see <http://www.gnu.org/licenses/>.

CACHE_DIR='/var/cache/showme'
CACHE_TIMEOUT=900
NOW=`date +%s`
TRIM=0
SHORT=0
CACHE=0
INTERFACES='eth0'
SCOPES='Link Local Global'
PROTOS='4 6'

get_cache() {
    if test $CACHE -eq 1 && \
       _cache_last_mod=`stat --printf=%Y "${CACHE_DIR}/$1" 2>/dev/null` && \
       test `expr $NOW - $_cache_last_mod` -lt $CACHE_TIMEOUT && \
       _output="$(cat "${CACHE_DIR}/$1")" && \
       test -n "$_output"; then
        printf '%s\n' "$_output"
        return 0
    else
        return 1
    fi
}

put_cache() {
    if test 0 -eq $CACHE; then
        cat
    else
        tee "${CACHE_DIR}/$1" 2>/dev/null
    fi
}

put_cache_n() { put_cache "$@" >/dev/null; }

usage() {
    cat <<EOF
Usage: ${0##*/} [OPTIONS] [--] COMMAND

TODO...

OPTIONS
 TODO...
EOF
}

while test $# -ne 0; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -t|--trim)
            TRIM=1
            shift
            ;;
        -s|--short)
            SHORT=1
            shift
            ;;
        -c|--cache)
            CACHE=1
            shift
            ;;
        -i|--interfaces)
            INTERFACES="$2"
            shift 2
            ;;
        -S|--scopes)
            SCOPES="$2"
            shift 2
            ;;
        -p|--protocols)
            PROTOS="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -*)
            usage >&2
            printf '* Invalid option "%s". Aborting.\n' >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done
case "$1" in
    ip|hostname)
        COMMAND="$1"
        ;;
    *)
        usage >&2
        printf '* Invalid argument. Aborting.\n' >&2
        exit 1
        ;;
esac

case "$COMMAND" in

    ip)
        for _intf in $INTERFACES; do
            _ifconfig_output="$(/sbin/ifconfig "$_intf")"
            for _proto in $PROTOS; do
                case "$_proto" in
                    4)
                        _grep_field='inet'
                        ;;
                    6)
                        _grep_field='inet6'
                        ;;
                    *)
                        printf 'oops\n' >&2
                        exit 1
                        ;;
                esac
                _proto_grep="$(
                    printf '%s\n' "$_ifconfig_output" | \
                        sed -n -e 's/^[ \t]\+'"$_grep_field"' addr:[ \t]*//; t PRINT; b; : PRINT; p'
                )"
                for _scope in $SCOPES; do
                    case "$_proto" in
                        6)
                            case "$_scope" in
                                Link|Local|Global)
                                    _ip="`
                                        printf '%s\n' "$_proto_grep" | \
                                            sed -n -e 's/^\([^ \t]\+\)[ \t].*'"$_scope"'.*$/\1/; t PRINT; b; : PRINT; p; q'
                                    `"
                                    :
                                    ;;
                                *)
                                    printf 'oops\n' >&2
                                    exit 1
                                    ;;
                            esac
                            ;;
                        4)
                            case "$_scope" in
                                Link)
                                    _ip='127.0.0.1'
                                    ;;
                                *)
                                    _ip="`
                                        printf '%s\n' "$_proto_grep" | \
                                            sed -n -e 's/^\([^ \t]\+\)[ \t].*$/\1/; p; q'
                                    `"
                                    case "$_ip" in
0.*|\
10.*|\
100.6[4-9].*|\
100.[7-9][0-9].*|\
100.1[0-1][0-9].*|\
100.12[0-7].*|\
127.*|\
169.254.*|\
172.1[6-9].*|\
172.2[0-9].*|\
172.3[0-1].*|\
192.0.0.*|192.0.2.*|192.88.99.*|192.168.*|\
198.1[8-9].*|198.51.100.*|\
203.0.113.*)
                                            if ! test 'Local' = "$_scope"; then
                                                _ip="`get_cache "ip_${_intf}_${_proto}_${_scope}"`" || \
                                                    _ip="`
                                                        wget -O- "http://icanhazip.com" 2>/dev/null | \
                                                            put_cache "ip_${_intf}_${_proto}_${_scope}"
                                                    `"
                                            fi
                                            ;;
                                        *)
                                            test 'Global' = "$_scope" || _ip=''
                                            ;;
                                    esac
                                    ;;
                            esac
                            ;;
                    esac
                    if test $TRIM -eq 0 || test -n "$_ip"; then
                        test $SHORT -eq 1 || printf '%s:v%d:%s:' "$_intf" "$_proto" "$_scope"
                        printf '%s\n' "$_ip"
                    fi
                done
            done
        done
        ;;

    hostname)
        _cacheflag=''
        test $CACHE -eq 0 || _cacheflag='-c'
        IPS=`"$0" $_cacheflag -i "$INTERFACES" -S "$SCOPES" -p "$PROTOS" -- ip`
        for _intf in $INTERFACES; do
            for _scope in $SCOPES; do
                _ip4="`printf '%s\n' "$IPS" | sed -n -e "s/^${_intf}:v4:${_scope}://; t PRINT; b; : PRINT; p"`"
                _ip6="`printf '%s\n' "$IPS" | sed -n -e "s/^${_intf}:v6:${_scope}://; t PRINT; b; : PRINT; p"`"
                case "$_scope" in
                    Link)
                        _host="`hostname`"
                        ;;
                    Local)
                        _host="`hostname -f`"
                        ;;
                    Global)
                        _host="`get_cache "hostname_${_intf}_${_scope}"`" || {
                            _host="`dig -x "$_ip4" +time=1 2>/dev/null | sed -n -e 's/^[^;].*[ \t]\([^ \t]*[^.]\)\.\?$/\1/; t PRINT; b; : PRINT; p; q'`"
                            test -n "$_host" || test -z "$_ip6" || \
                                _host="`dig -x -6 "$_ip6" +time=1 2>/dev/null | sed -n -e 's/^[^;].*[ \t]\([^ \t]*[^.]\)\.\?$/\1/; t PRINT; b; : PRINT; p; q'`"
                            test -n "$_host" || \
                                _host="`wget --timeout=1 -O- "http://icanhazptr.com" 2>/dev/null`"
                            test -n "$_host" || \
                                _host="`wget -6 --timeout=1 -O- "http://icanhazptr.com" 2>/dev/null`"
                            test -n "$_host" || _host="`hostname -f 2>/dev/null`"
                            test -z "$_host" || \
                                printf '%s\n' "$_host" | put_cache_n "hostname_${_intf}_${_scope}"
                        }
                        ;;
                    *)
                        printf 'oops' >&2
                        exit 1
                        ;;
                esac
                if test $TRIM -eq 0 || test -n "$_host"; then
                    test $SHORT -eq 1 || printf '%s:%s:' "$_intf" "$_scope"
                    printf '%s\n' "$_host"
                fi
            done
        done
        ;;

esac
