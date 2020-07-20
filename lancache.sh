#!/bin/bash

initcolours() {
    if test -t 1; then
        # see if it supports colors...
        ncolors=$(tput colors)

        if test -n "$ncolors" && test $ncolors -ge 8; then
            bold="$(tput bold)"
            underline="$(tput smul)"
            standout="$(tput smso)"
            normal="$(tput sgr0)"
            black="$(tput setaf 0)"
            red="$(tput setaf 1)"
            green="$(tput setaf 2)"
            yellow="$(tput setaf 3)"
            darkblue="$(tput setaf 4)"
            magenta="$(tput setaf 5)"
            blue="$(tput setaf 6)"
            white="$(tput setaf 7)"
            bgred=$(echo "\033[41m")
        fi
    fi
}
initcolours

disablecolours() {
    bold=""
    underline=""
    standout=""
    normal=""
    black=""
    red=""
    green=""
    yellow=""
    darkblue=""
    magenta=""
    blue=""
    white=""
    bgred=""
}

show_main_menu() {
    if [ -z "$1" ] && [ "$1" != "0" ]; then
        clear
    fi
    msg=$2
    printf "${blue}*********************************************${normal}\n"
    if [ ! -z "$msg" ]; then
        printf "${yellow}** ${msg} ${normal}\n"
    fi
    printf "${blue}****** Please pick an option from below *****${normal}\n"
    printf "${blue}**${yellow} 1)${blue} Run checks and run Lancache ${normal}\n"
    printf "${blue}**${yellow} 2)${blue} Configure Lancache ${normal}\n"
    printf "${blue}**${yellow} 3)${blue} Check environment ${normal}\n"
    printf "${blue}**${yellow} 4)${blue} Ignore checks and run Lancache ${normal}\n"
    if [ "$(get_autostart_status)" == "ENABLED" ]; then
        printf "${blue}**${yellow} 5)${blue} Disable autostart ${normal}\n"
    else
        printf "${blue}**${yellow} 5)${blue} Enable autostart ${normal}\n"
    fi
    printf "${blue}**${yellow} 6)${blue} Update & restart containers ${normal}\n"
    printf "${blue}*********************************************${normal}\n"
    printf "Please select a menu option and enter or ${red}x to exit. ${normal}"
    read -n1 mm_answer
}

check_environment() {
    # TODO:
    # Check if storage is on nfs or cifs
    # Make the systemd-resolved check a bit more intelligent
    # Add other recommended docker versions 
    # Check if the lancache IP is RFC1918 compliant
    clear
    full=$1 || 0
    dontrun=0
    printf "${blue}*********************************************${normal}\n"
    printf "${blue}** Beginning environment check ${normal}\n"
    printf "${blue}*********************************************${normal}\n"
    docker_test=$(docker ps)
    docker_test_rc=$?
    if [ $docker_test_rc != "0" ]; then
        printf "${bgred}XX Looks like there is something wrong with docker (RC: ${docker_test_rc}) ${normal}\n"
        printf "${bgred}XX Please ensure Docker is running, and the current user is part of the 'docker' group ${normal}\n"
        dontrun=1
    else
        printf "${blue}** Docker is running ${normal}\n"
    fi
    docker_version=$(docker version --format '{{.Server.Version}}')
    recommended_docker_versions="19.03.8#1.0.0"
    if [[ ! $recommended_docker_versions =~ $docker_version ]]; then
        printf "${yellow}** Your docker version doesn't look to be recommended. This shouldn't cause a problem, but could definitely do with being corrected (Version ${docker_version}) ${normal}\n"
        dontrun=1
    else
        printf "${blue}** Docker version is recommended ${normal}\n"
    fi

    docker_compose_test=$(docker-compose -v)
    docker_compose_test_rc=$?

    if [ $docker_test_rc != "0" ]; then
        printf "${bgred}XX docker-compose isn't installed, or is not executable. (RC: ${docker_compose_test_rc}) ${normal}\n"
        dontrun=1
    else
        printf "${blue}** docker-compose is installed ${normal}\n"
    fi

    if [ $(which systemd) != "systemd not found" ]; then
        # This could do with fluffing to deal with more conditions
        resolved_test=$(systemctl status systemd-resolved)
        resolved_test_rc=$?
        if [ $resolved_test_rc == 0 ]; then
            printf "${bgred}XX systemd-resolved is not in expected state (RC: ${resolved_test_rc}) ${normal}\n"
            printf "${yellow}** This will collide with the lancache-dns image. Please ignore this error if you intend to host the DNS element elsewhere. ${normal}\n"
            printf "${yellow}** There is a known fix for this: http://lancache.net/docs/common-issues/#disabling-systemd-resolved-dnsstublistener ${normal}\n"
            systemctl status systemd-resolved
            echo ""
            dontrun=1
        fi
    fi

    load_env
    if [ -z $LANCACHE_IP ]; then
        printf "${bgred}XX LANCACHE_IP is not set in .env ${normal}\n"
        dontrun=1
    fi
    if [ -z $UPSTREAM_DNS ]; then
        printf "${bgred}XX UPSTREAM_DNS is not set in .env ${normal}\n"
        dontrun=1
    fi
    if [ "${UPSTREAM_DNS}" == "${LANCACHE_IP}" ] && [ ! -z $LANCACHE_IP ]; then
        printf "${bgred}XX UPSTREAM_DNS is the same as your LANCACHE_IP (${UPSTREAM_DNS} == ${LANCACHE_IP}) - this will cause a loop ${normal}\n"
        dontrun=1
    fi
    if [ $(command -v dig) != "" ]; then
        dns_test=$(dig @${UPSTREAM_DNS} +short lancache.steamcontent.com)
        if [ "${dns_test}" == "${LANCACHE_IP}" ]; then
            printf "${bgred}XX UPSTREAM_DNS is resolving lancache.steamcontent.com to the same value as LANCACHE_IP (${LANCACHE_IP}) - this will cause a loop ${normal}\n"
            dontrun=1
        fi
    fi

    if [ "${CACHE_MEM_SIZE}" != "500m" ]; then
        printf "${yellow}** Your CACHE_MEM_SIZE is not default (${CACHE_MEM_SIZE} != 500m), make sure you know what you're doing if you change this ${normal}\n"
    fi

    if [ "${CACHE_MAX_AGE}" != "3650d" ]; then
        printf "${yellow}** Your CACHE_MAX_AGE is not default (${CACHE_MAX_AGE} != 3650d), make sure you know what you're doing if you change this ${normal}\n"
    fi

    if [ -d $(dirname $0)/$CACHE_ROOT ]; then
        # A perm check should go here
        echo .
    else
        printf "${yellow}** Your CACHE_ROOT (${CACHE_ROOT}) does not exist ${normal}\n"
    fi

    if [ "${shouldrun}" == 1 ]; then
        printf "${blue}** Everything looks okay.${normal}\n"
    else 
        printf "${blue}** Problems found. They are listed with a red background, or prefaced with XX.${normal}\n"
        printf "${blue}** There may also be some recommended changes listed in yellow.${normal}\n"
        printf "${blue}** It is recommended you correct these before continuing.${normal}\n"
    fi
    printf "${blue}** Make sure you have read the FAQ (${yellow}http://lancache.net/docs/faq/${blue}) if you have any yellow points ${normal}\n"
    printf "${blue}** If you still have questions, the Lancache Discord can be found at ${yellow}https://discord.gg/BKnBS4u ${normal}\n"
    printf "${blue}*********************************************${normal}\n"
    return $dontrun
}

load_env() {
    . $(dirname $0)/.env
}

show_configure_menu() {
    clear
    load_env
    printf "${blue}*********************************************${normal}\n"
    printf "${blue}****** Please pick an option from below *****${normal}\n"
    if [ -z $LANCACHE_IP ]; then
        printf "${blue}**${yellow} 1)${red} Set LANCACHE_IP [not set] ${normal}\n"
    else 
        printf "${blue}**${yellow} 1)${blue} Set LANCACHE_IP [${LANCACHE_IP}] ${normal}\n"
    fi
    if [ -z $DNS_BIND_IP ]; then
        printf "${blue}**${yellow} 2)${red} Set DNS_BIND_IP [not set] ${normal}\n"
    else 
        printf "${blue}**${yellow} 2)${blue} Set DNS_BIND_IP [${DNS_BIND_IP}] ${normal}\n"
    fi
    if [ -z $UPSTREAM_DNS ]; then
        printf "${blue}**${yellow} 3)${red} Set UPSTREAM_DNS [not set] ${normal}\n"
    else 
        printf "${blue}**${yellow} 3)${blue} Set UPSTREAM_DNS [${UPSTREAM_DNS}] ${normal}\n"
    fi
    printf "${blue}**${yellow} 4)${blue} Set CACHE_ROOT [${CACHE_ROOT}] ${normal}\n"
    printf "${blue}**${yellow} 5)${blue} Set CACHE_DISK_SIZE [${CACHE_DISK_SIZE}] ${normal}\n"
    printf "${blue}**${yellow} 6)${blue} Set CACHE_MEM_SIZE [${CACHE_MEM_SIZE}] ${normal}\n"
    printf "${blue}**${yellow} 7)${blue} Set CACHE_MAX_AGE [${CACHE_MAX_AGE}] ${normal}\n"
    printf "Please select a menu option or ${red}x to return to main menu. ${normal}"
    read -n1 cm_answer
}

check_valid_v4() {
    local ip=${1:-1.2.3.4}
    local IFS=.
    local -a a=($ip)
    if [[ ! $ip =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
        return 1
    fi
    local quad
    for quad in {0..3}; do
        if [[ "${a[$quad]}" -gt 255 ]]; then
            return 1
        fi
    done
    return 0
}

configure_menu() {
    show_configure_menu
    while [ "${cm_answer}" != '' ]; do
        if [ "${cm_answer}" == '' ]; then
            return;
        fi
        echo ""
        case "${cm_answer}" in
            1)
                while [ true ]; do
                    current=""
                    if [ ! -z $LANCACHE_IP ]; then
                        current="[ $LANCACHE_IP ]"
                    fi
                    printf "${blue}Please enter the new LANCACHE_IP: ${current}${normal} "
                    read response 
                    if [ "${response}" == '' ]; then
                        response=$LANCACHE_IP
                    fi
                    valid=$(check_valid_v4 "${response}")
                    if [ "${valid}" == "1" ]; then
                        echo "Invalid IPv4 address: ${response}"
                        continue;
                    fi
                    break
                done
                sed -iE "s/^LANCACHE_IP=.*$/LANCACHE_IP=${response}/" $(dirname $0)/.env
                show_configure_menu
            ;;
            2)
                while [ true ]; do
                    current=""
                    if [ ! -z $DNS_BIND_IP ]; then
                        current="[ $DNS_BIND_IP ]"
                    fi
                    printf "${blue}Please enter the new DNS_BIND_IP: ${current}${normal} "
                    read response 
                    if [ "${response}" == '' ]; then
                        response=$DNS_BIND_IP
                    fi
                    valid=$(check_valid_v4 "${response}")
                    if [ "${valid}" == "1" ]; then
                        echo "Invalid IPv4 address: ${response}"
                        continue;
                    fi
                    break
                done
                sed -iE "s/^DNS_BIND_IP=.*$/DNS_BIND_IP=${response}/" $(dirname $0)/.env
                show_configure_menu
            ;;
            3)
                while [ true ]; do
                    current=""
                    if [ ! -z $UPSTREAM_DNS ]; then
                        current="[ $UPSTREAM_DNS ]"
                    fi
                    printf "${blue}Please enter the new UPSTREAM_DNS: ${current}${normal} "
                    read response 
                    if [ "${response}" == '' ]; then
                        response=$UPSTREAM_DNS
                    fi
                    valid=$(check_valid_v4 "${response}")
                    if [ "${valid}" == "1" ]; then
                        echo "Invalid IPv4 address: ${response}"
                        continue;
                    fi
                    break
                done
                sed -iE "s/^UPSTREAM_DNS=.*$/UPSTREAM_DNS=${response}/" $(dirname $0)/.env
                show_configure_menu
            ;;
            4)
                while [ true ]; do
                    current=""
                    if [ ! -z $CACHE_ROOT ]; then
                        current="[ $CACHE_ROOT ]"
                    fi
                    printf "${blue}Please enter the new CACHE_ROOT: ${current}${normal} "
                    read response 
                    if [ "${response}" == '' ]; then
                        response=$CACHE_ROOT
                    fi
                    break
                done
                sed -iE "s/^CACHE_ROOT=.*$/CACHE_ROOT=${response}/" $(dirname $0)/.env
                show_configure_menu
            ;;
            5)
                while [ true ]; do
                    current=""
                    if [ ! -z $CACHE_DISK_SIZE ]; then
                        current="[ $CACHE_DISK_SIZE ]"
                    fi
                    printf "${blue}Please enter the new CACHE_DISK_SIZE: ${current}${normal} "
                    read response 
                    if [ "${response}" == '' ]; then
                        response=$CACHE_DISK_SIZE
                    fi
                    break
                done
                sed -iE "s/^CACHE_DISK_SIZE=.*$/CACHE_DISK_SIZE=${response}/" $(dirname $0)/.env
                show_configure_menu
            ;;
            6)
                while [ true ]; do
                    current=""
                    if [ ! -z $CACHE_MEM_SIZE ]; then
                        current="[ $CACHE_MEM_SIZE ]"
                    fi
                    printf "${blue}Please enter the new CACHE_MEM_SIZE: ${current}${normal} "
                    read response 
                    if [ "${response}" == '' ]; then
                        response=$CACHE_MEM_SIZE
                    fi
                    break
                done
                sed -iE "s/^CACHE_MEM_SIZE=.*$/CACHE_MEM_SIZE=${response}/" $(dirname $0)/.env
                show_configure_menu
            ;;
            7)
                while [ true ]; do
                    current=""
                    if [ ! -z $CACHE_MAX_AGE ]; then
                        current="[ $CACHE_MAX_AGE ]"
                    fi
                    printf "${blue}Please enter the new CACHE_MAX_AGE: ${current}${normal} "
                    read response 
                    if [ "${response}" == '' ]; then
                        response=$CACHE_MAX_AGE
                    fi
                    break
                done
                sed -iE "s/^CACHE_MAX_AGE=.*$/CACHE_MAX_AGE=${response}/" $(dirname $0)/.env
                show_configure_menu
            ;;
            x)
                return;
            ;;
            \n)
                return;
            ;;
            *)
                option_picked "Pick an option from the menu";
                show_main_menu;
            ;;
        esac
    done
}

start_cache() {
    pushd $(dirname $0)
    docker-compose up -d
    popd
}

get_autostart_status() {
    test=$(cat $(dirname $0)/docker-compose.yml | grep "#    restart")
    if [ "$test" == "" ]; then
        echo "ENABLED"
        return
    fi
    echo "DISABLED"
}

toggle_autostart() {
    if [ $(get_autostart_status) == "ENABLED" ]; then
        sed -iE "s/    restart: unless-stopped/#    restart: unless-stopped/" $(dirname $0)/docker-compose.yml
        echo "Disabled autostart"
    else
        sed -iE "s/#    restart: unless-stopped/    restart: unless-stopped/" $(dirname $0)/docker-compose.yml
        echo "Enabled autostart"
    fi
}

update_restart() {
    printf "${blue}*********************************************${normal}\n"
    printf "${yellow}** This will restart your containers and interrupt service\n"
    printf "${yellow}** Press Y to continue, or any key to cancel ${normal}\n"
    read -n 1 restart
    if [ "${restart}" =~ ^[Yy]$ ]; then
        return
    fi
    pushd $(dirname $0)
    docker-compose pull
    docker-compose stop
    docker-compose up -d
    popd
}

main_menu() {
    show_main_menu
    while [ "${mm_answer}" != '' ]; do
        if [ "${mm_answer}" == '' ]; then
            exit;
        fi
        echo ""
        case "${mm_answer}" in
            1)
                check_environment
                rc=$?
                if [ $rc == 0 ]; then
                    printf "${bgred}Aborting startup${normal}\n"
                else
                    start_cache
                fi
                show_main_menu 
            ;;
            2)
                configure_menu
                show_main_menu
            ;;
            3)
                check_environment
                show_main_menu 0
            ;;
            4)
                start_cache
                show_main_menu 
            ;;
            5)
                show_main_menu 0 "$(toggle_autostart)"
            ;;
            6)
                update_restart
                show_main_menu 0
            ;;
            x)
                exit;
            ;;
            \n)
                exit;
            ;;
            *)
                show_main_menu;
            ;;
        esac
    done
}

main_menu