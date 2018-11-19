#!/usr/bin/env bash
#
# valet.sh
#
# Copyright: (C) 2018 TechDivision GmbH - All Rights Reserved
# Author: Johann Zelger <j.zelger@techdivision.com>

#######################################
# Toggles spinner animation
# Globals:
#   SPINNER_PID
# Arguments:
#   Message
# Returns:
#   None
#######################################
spinner_toogle() {

    # Start spinner background function
    function _spinner_start() {
        local list=( $(echo -e '\xe2\xa0\x8b')
                     $(echo -e '\xe2\xa0\x99')
                     $(echo -e '\xe2\xa0\xb9')
                     $(echo -e '\xe2\xa0\xb8')
                     $(echo -e '\xe2\xa0\xbc')
                     $(echo -e '\xe2\xa0\xb4')
                     $(echo -e '\xe2\xa0\xa6')
                     $(echo -e '\xe2\xa0\xa7')
                     $(echo -e '\xe2\xa0\x87')
                     $(echo -e '\xe2\xa0\x8f') )
        local i=0
        tput sc
        # wait for .inprogress flag file to be created by ansible callback plugin
        while [ ! -f "$BASE_DIR/.inprogress" ]; do sleep 0.5; done
        while true; do
            printf "\e[32m%s\e[39m $1 " "${list[i]}"
            ((i++))
            ((i%10))
            sleep 0.1
            tput rc
        done
    }

    # check if spinner pid exist
    if [[ "$SPINNER_PID" -lt 1 ]]; then
        tput sc
        _spinner_start "$1" &
        SPINNER_PID=$!
    else
        kill $SPINNER_PID > /dev/null 2>&1
        wait $! 2>/dev/null
        SPINNER_PID=0
        tput rc
    fi

}


#######################################
# Logs messages in given type
# Globals:
#   None
# Arguments:
#   Message
#   Type
# Returns:
#   None
#######################################
function log {
    if [[ -n "$LOG_FILE" && -w "$LOG_FILE" ]]; then
        logtext=""
        case "${1--h}" in
            error) logtext="\033[1m\033[31m✘ $2\033[0m";;
            success) logtext="\033[1\033[32m✔ $2\033[0m";;
            debug) if [ "$DEBUG_ENABLED" = true ]; then
                        logtext="# debug: $2"
                   else
                        echo -e "# Debug: $2" >> "$LOG_FILE"
                   fi;;
            *) printf "%s\n" "$2";;
        esac

        echo -e "$logtext" >> "$LOG_FILE"
        echo -e "$logtext"
    else
        echo -e "ERROR: LOG_FILE \"$LOG_FILE\" is not writeable!"
        if [ "$DEBUG_ENABLED" ]; then
            echo -e "# DEBUG: $2"
        fi
    fi
}


#######################################
# Validates version against semver
# Globals:
#   None
# Arguments:
#   Version
# Returns:
#   None
#######################################
function version_validate {
    local version=$1
    if [[ "$version" =~ $SEMVER_REGEX ]]; then
        if [ "$#" -eq "2" ]; then
            local major=${BASH_REMATCH[1]}
            local minor=${BASH_REMATCH[2]}
            local patch=${BASH_REMATCH[3]}
            local prere=${BASH_REMATCH[4]}
            local build=${BASH_REMATCH[5]}
            eval "$2=(\"$major\" \"$minor\" \"$patch\" \"$prere\" \"$build\")"
        else
            echo "$version"
        fi
    else
        log error "Version $version does not match the semver scheme 'X.Y.Z(-PRERELEASE)(+BUILD)'. See help for more information." error
    fi
}

#######################################
# Compares versions
# Globals:
#   None
# Arguments:
#   Version1
#   Version2
# Returns:
#  -1   if version1 < version2
#   0   if version1 == version2
#   1   if version1 > version2
#######################################
function version_compare {
    version_validate "$1" V
    version_validate "$2" V_

    for i in 0 1 2; do
        local diff=$((${V[$i]} - ${V_[$i]}))
        if [[ $diff -lt 0 ]]; then
            echo -1; return 0
        elif [[ $diff -gt 0 ]]; then
            echo 1; return 0
        fi
    done

    if [[ -z "${V[3]}" ]] && [[ -n "${V_[3]}" ]]; then
        echo -1; return 0;
    elif [[ -n "${V[3]}" ]] && [[ -z "${V_[3]}" ]]; then
        echo 1; return 0;
    elif [[ -n "${V[3]}" ]] && [[ -n "${V_[3]}" ]]; then
        if [[ "${V[3]}" > "${V_[3]}" ]]; then
            echo 1; return 0;
        elif [[ "${V[3]}" < "${V_[3]}" ]]; then
          echo -1; return 0;
        fi
    fi

    echo 0
}

#######################################
# Set and get global variables
# Globals:
#   APPLICATION_RETURN_CODE
#   APPLICATION_START_TIME
#   APPLICATION_NAME
#   APPLICATION_MODE
#   APPLICATION_GIT_URL
#   APPLICATION_GIT_API_URL
#   SEMVER_REGEX
#   ANSIBLE_PLAYBOOKS_DIR
#   INSTALL_DIR
#   CLI_TMP_WORKDIR
#   APPLICATION_VERSION
#   DEPENDENCIES_FULLFILLED
# Arguments:
#   None
# Returns:
#   None
#######################################
function init {
    APPLICATION_RETURN_CODE=0
    APPLICATION_START_TIME=$(ruby -e 'puts Time.now.to_f');
    # define variables
    APPLICATION_NAME="valet.sh"
    : "${APPLICATION_MODE:=production}"
    APPLICATION_GIT_URL=${APPLICATION_GIT_URL:="https://github.com/valet-sh/valet-sh"}
    APPLICATION_GIT_API_URL=${APPLICATION_GIT_API_URL:="https://api.github.com/repos/valet-sh/valet-sh"}

    SEMVER_REGEX="^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$"

    ANSIBLE_PLAYBOOKS_DIR="playbooks"
    INSTALL_DIR="$HOME/.${APPLICATION_NAME}";

    # Check in which environment the CLI tool is, running from remote, is there a local installation already, what is CLI_BASE_DIR, CLI_SCRIPT_PATH...
    cli_check_environment
    INIT_DEBUGLOG+="\n# debug: Selecting \"$CLI_BASE_DIR\" as CLI_BASE_DIR"

    # Create temporary workdir for CLI, if it's not yet installed
    if [ "$CLI_IS_INSTALLED" = false ]; then
        CLI_TMP_WORKDIR="/tmp/$APPLICATION_NAME"
        cli_prepare_tmp_workdir
    fi

    # set LOG_PATH and prepare logfile
    prepare_logfile

    # todo : Checks in separate function check_deps --> DEPENDENCIES_FULLFILLED
    # still needed?

	print_header
}

#######################################
# Check in which environment the CLI tool is, running from remote, is there a local installation already, what is CLI_BASE_DIR, CLI_SCRIPT_PATH...
# Globals:
#   CLI_IS_INSTALLED
#   CLI_FROM_REMOTE
#   OSTYPE
#   CLI_SCRIPT_PATH
#   CLI_BASE_DIR
#   APPLICATION_VERSION
# Arguments:
#   None
# Returns:
#   None
#######################################
function cli_check_environment {
    # get SCRIPT_PATH - resolve symlink if needed
    # Todo: early MacOS does not have BASH_SOURCE use $0 or something else
    test -h "${BASH_SOURCE[0]}" && CLI_SCRIPT_PATH="$(readlink "${BASH_SOURCE[0]}")" || CLI_SCRIPT_PATH="${BASH_SOURCE[0]}"
    # get BASE_DIR - current bash script dirname
    CLI_BASE_DIR="$( dirname "${CLI_SCRIPT_PATH}" )"

    if [[ -d "$INSTALL_DIR" && -x "$INSTALL_DIR/.${APPLICATION_NAME}" ]]; then
        INIT_DEBUGLOG+="\n# debug: Found a existing $APPLICATION_NAME installation in \"$INSTALL_DIR\"!"
        CLI_IS_INSTALLED=true

        if [[ "$CLI_SCRIPT_PATH" -eq "$INSTALL_DIR/.${APPLICATION_NAME}" ]]; then
            INIT_DEBUGLOG+="\n# debug: Running $APPLICATION_NAME locally from INSTALL_DIR \"$INSTALL_DIR\""
            CLI_FROM_REMOTE=false
            if [ -r "$INSTALL_DIR/.installed_version" ]; then
                APPLICATION_VERSION=$(cat "$INSTALL_DIR/.installed_version")
            else
                APPLICATION_VERSION="MISSING APPLICATION_VERSION"
            fi
            # todo: set_application_version function
            #if [ -d $INSTALL_DIR ]; then
                # get the current version from git
            #    APPLICATION_VERSION=$(git --git-dir="${BASE_DIR}/.git" --work-tree="${BASE_DIR}" describe --tags)
            #fi
        else
            INIT_DEBUGLOG+="\n# debug: Running $APPLICATION_NAME not installed (!) but remotely started from \"$CLI_SCRIPT_PATH\"!"
            CLI_FROM_REMOTE=true
        fi
    else
        INIT_DEBUGLOG+="\n# debug: Running $APPLICATION_NAME NOT INSTALLED from \"$CLI_SCRIPT_PATH\"!"
        CLI_FROM_REMOTE=true && CLI_IS_INSTALLED=false
    fi

    # Todo allow only MacOS incl 10.12 else: APPLICATION_RETURN_CODE ++ shutdown A
    OSTYPE="unsupported"
    if [[ $(uname -s) == "Darwin" ]]
	 then
	    OSTYPE="mac"
	elif [[ $(uname -s) == "Linux" ]]
	 then
		OSTYPE="linux"
    else
		# fallback to macos
		OSTYPE="mac"
	fi
}

#######################################
# Prepare a temporary workdir in /tmp/$APPLICATION_NAME
# Globals:
#   APPLICATION_VERSION
# Arguments:
#   None
# Returns:
#   None
#######################################
function cli_prepare_tmp_workdir {
    if [ ! -d "$CLI_TMP_WORKDIR" ]; then
        mkdir "$CLI_TMP_WORKDIR" || shutdown "Failed to create CLI_TMP_WORKDIR"
    else
        if [[ ${#CLI_TMP_WORKDIR} -gt 5 ]]; then
            rm ${CLI_TMP_WORKDIR:0}/*
            INIT_DEBUGLOG+="\n# debug: Cleared orphaned CLI_TMP_WORKDIR \"$CLI_TMP_WORKDIR\""
        fi
    fi
}

#######################################
# Enable debug mode
# Globals:
#   DEBUG_ENABLED
# Arguments:
#   None
# Returns:
#   None
#######################################
function cli_enable_debug {
    DEBUG_ENABLED=true
    # log any debug from init function
    log debug "$INIT_DEBUGLOG\n"
}

#######################################
# Run a initial prepare job depending on OS
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
function prepare {
    if [ "$OSTYPE" = "macos" ]
     then
        install_macos_deps
    fi

    # check if git dir is available
    #if [ -d "$INSTALL_DIR/.git" ]; then
    #    # set cwd to base dir, note: for development use this will be different from $INSTALL_DIR
    #    cd "$BASE_DIR"
    #fi

}

#######################################
# Install ansible if not available
# Globals:
#   SOFTWARE_UPDATE_NAME
# Arguments:
#   None
# Returns:
#   None
#######################################
function install_macos_deps {
    # check if macOS command line tools are available by checking git bin
    if [ ! -f /Library/Developer/CommandLineTools/usr/bin/git ]; then
        spinner_toogle "Installing CommandLineTools \e[32m$command\e[39m"
        # if git command is not available, install command line tools
        # create macOS flag file, that CommandLineTools can be installed on demand
        touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
        # install command line tools
        SOFTWARE_UPDATE_NAME=$(softwareupdate -l | grep -B 1 -E "Command Line Tools.*$(sw_vers -productVersion)" | awk -F'*' '/^ +\*/ {print $2}' | sed 's/^ *//' | tail -n1)
        softwareupdate -i "$SOFTWARE_UPDATE_NAME"
        # cleanup in-progress file for macos softwareupdate util
        rm -rf /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
        spinner_toogle
    fi
    # check if ansible command is available
    if [ ! -x "$(command -v ansible)" ]; then
        spinner_toogle "Installing Ansible \e[32m$command\e[39m"
        # if ansible is not available, install pip and ansible
        sudo easy_install pip;
        sudo pip install -Iq ansible;
        spinner_toogle
    fi
}

#######################################
# Install and upgrade logic
# Globals:
#   APPLICATION_NAME
#   APPLICATION_VERSION
#   APPLICATION_GIT_URL
#   BASE_DIR
# Arguments:
#   None
# Returns:
#   None
#######################################
function install_upgrade {

    # run os-dependent ansible init playbook
    execute_ansible_playbook init

    # reset release tag to current application version
    RELEASE_TAG=$APPLICATION_VERSION

    if [ $APPLICATION_MODE = "production" ]; then
        # create tmp directory for cloning CLI
        local tmp_dir=$(mktemp -d)
        local src_dir=$tmp_dir

        # clone project git repo to tmp dir
        rm -rf "$tmp_dir"
        git clone --quiet $APPLICATION_GIT_URL "$tmp_dir"
        cd "$tmp_dir"

        # fetch all tags from application git repo
        git fetch --tags

        # get available release tags sorted by refname
        RELEASE_TAGS=$(git tag --sort "-v:refname" )

        # get latest semver conform git version tag on current major version releases
        for GIT_TAG in $RELEASE_TAGS; do
            if [[ "$GIT_TAG" =~ $SEMVER_REGEX ]]; then
                RELEASE_TAG="$GIT_TAG"
                break;
            fi
        done

        # force checkout latest release tag in given major version
        git checkout --quiet --force "$RELEASE_TAG"
    else
        # take base dir for developer installation
        src_dir=$CLI_BASE_DIR
    fi

    # check if install dir exist
    if [ ! -d "$INSTALL_DIR" ]; then
        # install
        cp -r "$src_dir" "$INSTALL_DIR"
        # create symlink to default included PATH
        sudo ln -sf "$INSTALL_DIR/${APPLICATION_NAME}" /usr/local/bin
        # output log
        log success "Installed version $RELEASE_TAG"
    else
        CURRENT_INSTALLED_VERSION=$(git --git-dir=${INSTALL_DIR}/.git --work-tree=${INSTALL_DIR} describe --tags)
        # compare application version to release tag version
        if [ $(version_compare ${CURRENT_INSTALLED_VERSION} $RELEASE_TAG) -gt 0 ]; then
            log error "Already on the latest version $RELEASE_TAG"
        else
            log success "Upgraded from $CURRENT_INSTALLED_VERSION to latest version $RELEASE_TAG"
        fi

        # update tags
        git --git-dir=${INSTALL_DIR}/.git --work-tree=${INSTALL_DIR} fetch --tags --quiet
        # checkout target release tag
        git --git-dir=${INSTALL_DIR}/.git --work-tree=${INSTALL_DIR} checkout --force --quiet $RELEASE_TAG
    fi

    # change directory to install dir
    cd "$INSTALL_DIR"

    # clean tmp dir
    rm -rf "$tmp_dir"
}

#######################################
# Prints the console tool header
# Globals:
#   APPLICATION_NAME
#   APPLICATION_VERSION
#   APPLICATION_MODE
# Arguments:
#   None
# Returns:
#   None
#######################################
function print_header {
    echo -e "\033[1m\033[34m$APPLICATION_NAME\033[0m $APPLICATION_VERSION\033[0m"
    echo -e "\033[2m  (c) 2018 TechDivision GmbH\033[0m"
}

#######################################
# Prints the console tool header
# Globals:
#   LC_NUMERIC
#   APPLICATION_END_TIME
#   APPLICATION_EXECUTION_TIME
#   APPLICATION_NAME
#   APPLICATION_VERSION
#   APPLICATION_MODE
# Arguments:
#   None
# Returns:
#   None
#######################################
function print_footer {
    if [ "$DEBUG_ENABLED" = true ]; then
        LC_NUMERIC="en_US.UTF-8"

        APPLICATION_END_TIME=$(ruby -e 'puts Time.now.to_f')
        APPLICATION_EXECUTION_TIME=$(echo "$APPLICATION_END_TIME - $APPLICATION_START_TIME" | bc);

        printf "\n"
        printf "\e[34m"
        printf "\n"
        printf "\e[1mDebug information:\033[0m"
        printf "\e[34m"
        printf "\n"
        printf "  Version: \e[1m%s\033[0m\n" "$APPLICATION_VERSION"
        printf "\e[34m"
        printf "  Application mode: \e[1m%s\033[0m\n" "$APPLICATION_MODE"
        printf "\e[34m"
        printf "  Execution time: \e[1m%f sec.\033[0m\n" "$APPLICATION_EXECUTION_TIME"
        printf "\e[34m"
        printf "  Logfile: \e[1m%s\033[0m\n" "$LOG_FILE"
        printf "\e[34m"
        printf "  Exitcode: \e[1m%s\033[0m\n" "$APPLICATION_RETURN_CODE"
        printf "\e[34m\033[0m"
        printf "\n"
    fi
}

#######################################
# Print usage help and command list
# Globals:
#   BASE_DIR
# Arguments:
#   None
# Returns:
#   None
#######################################
function print_usage {
    local cmd_output_space='                                '
    printf "\e[33mUsage:\e[39m\n"
    printf "  command [options] [arguments]\n"
    printf "\n"
    printf "\e[32m  -h, --help            \e[39mDisplay this help message\n"
    printf "\e[32m  -v, --version         \e[39mDisplay this application version\n"
    printf "\n"
    printf "\e[33mAvailable commands:\e[39m\n"

    if [ -d "$CLI_BASE_DIR/playbooks" ]; then
        for file in ./playbooks/**.yml; do
            local cmd_name=$(basename $file .yml);
            local cmd_description=$(grep '^\#[[:space:]]@description:' -m 1 $file | awk -F'"' '{ print $2}');
            local cmd_visible=$(grep '^\#[[:space:]]@command:' -m 1 $file | awk -F'"' '{ print $2}');
            if [ -n "$cmd_visible" ]; then
                printf "  \e[32m%s %s \e[39m${cmd_description}\n" "$cmd_name" "${cmd_output_space:${#cmd_name}}"
            fi
        done
    fi

    if [ ! -d "$INSTALL_DIR" ]; then
        local cmd_name="install"
        local cmd_description="Installs $APPLICATION_NAME"
        printf "  \e[32m%s %s \e[39m${cmd_description}\n" $cmd_name "${cmd_output_space:${#cmd_name}}"
    fi

    shutdown
}

#######################################
# Prepares logfile
# Globals:
#   LOG_PATH
#   LOG_FILE
# Arguments:
#   Command
# Returns:
#   None
#######################################
function prepare_logfile {
    # set LOG_PATH and preprare logfile
    if [ "$CLI_IS_INSTALLED" = true ]; then
        LOG_PATH="$INSTALL_DIR/log"
    else
        LOG_PATH="$CLI_TMP_WORKDIR"
    fi
    # create LOG_PATH if not yet existent
    if [ ! -d "$LOG_PATH" ]; then
    # Todo: Implement fallback to /tmp/ if cannot create
        mkdir "$LOG_PATH" || echo -e "ERROR: Cannot create directory for logfiles \"$LOG_PATH\""
    fi
    tmp_log_file="$(mktemp -q ${LOG_PATH}/XXXXXXXXXXXXX)"
    LOG_FILE="${tmp_log_file}.log"
    mv "$tmp_log_file" "$LOG_FILE"

    if [ "$DEBUG_ENABLED" = true ];then
        INIT_DEBUGLOG+="\n# debug: Logfile-path is: $LOG_FILE"
    fi
}

#######################################
# Cleanup logfiles
# Globals:
#   LOG_PATH
# Arguments:
#   Command
# Returns:
#   None
#######################################
function cleanup_logfiles {
    # cleanup log directory and keep last 10 execution logs
    if [ -d "$LOG_PATH" ]; then
        cleanup_logfiles=$(ls -t1 "$LOG_PATH" | tail -n +11)
        test "$cleanup_logfiles" && rm "$cleanup_logfiles"
    fi
}

#######################################
# Executes command via ansible playbook
# Globals:
#   ANSIBLE_PLAYBOOKS_DIR
#   APPLICATION_RETURN_CODE
# Arguments:
#   Command
# Returns:
#   None
#######################################
function execute_ansible_playbook {
    log debug "Starting execute_ansible_playbook with parameters: $*"

    local command=$1
    local ansible_playbook_file="$ANSIBLE_PLAYBOOKS_DIR/$command.yml"
    local parsed_args=""
    local ansible_ret_code=0

    # prepare cli arguments if given and transform them to ansible extra vars format
    if [ "$#" -gt 1 ]; then
        for i in $(seq 2 $#); do  if [ $i -gt 2 ]; then parsed_args+=,; fi; parsed_args+="\"${!i}\""; done
    fi

    # define complete extra vars object
    read -r -d '' ansible_extra_vars << EOM
--extra-vars='{
    "cli": {
        "name": ${APPLICATION_NAME},
        "mode": ${APPLICATION_MODE},
        "version": ${APPLICATION_VERSION},
        "args": [${parsed_args}]
    }
}'
EOM

    # check if requested playbook yml exist and execute it
    if [ -f "$ansible_playbook_file" ]; then
        prepare_logfile

        spinner_toogle "Running \e[32m$command\e[39m"
        bash -c "ansible-playbook ${ansible_playbook_file} ${ansible_extra_vars}" &> ${LOG_FILE} || ansible_ret_code=$? && true
        spinner_toogle

        # log exact command line as typed in shell with user and path info
        echo "$PWD $USER: $0 $*" >> ${LOG_FILE}

        cleanup_logfiles

        # check if exit code was not 0
        if [ $ansible_ret_code != 0 ]; then
            log error
        else
            log success
        fi

    else
        log error "Command '$command' not available"
    fi

    # set global ret code like ansible ret code
    APPLICATION_RETURN_CODE=$ansible_ret_code
}

#######################################
# Shutdown cli client script
# Globals:
#   APPLICATION_RETURN_CODE
# Arguments:
#   Command
# Returns:
#   None
#######################################
function shutdown {
## Todo: cleanup logfile

    if [[ $# -gt 0 ]]; then
        log error "FATAL: $*"
    fi

    # exit with given return code
    exit $APPLICATION_RETURN_CODE
}


#######################################
# Initial cli client install routine
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
function install_cli_itself {
    log debug "Starting installation routine for CLI itself"

    # Ensure ansible command is available
    if [ ! -x "$(command -v ansible)" ]; then
        spinner_toogle "Installing Ansible"
        # if ansible is not available, install pip and ansible
        #log debug $(sudo easy_install pip)
        #log debug $(sudo pip install -Iq ansible)

        if [ ! -x "$(command -v ansible)" ]; then
            log error "Failed to install and access ansible!"
            #shutdown "Installation failed! REASON: ansible command not available"
        fi
        spinner_toogle
    else
        log debug "ok: Ansible accessible"
    fi

    if [ -x "$(command -v curl)" ]; then
        # Get current release tarball URL
        release_url="${APPLICATION_GIT_API_URL}/releases/latest"
            log debug "Checking releases at: $release_url"
        curl_content=$(curl --connect-timeout 10 -s "$release_url")
        if [ $? -gt 0 ]; then shutdown "Installation failed. REASON: cURL failed to access $APPLICATION_GIT_API_URL";fi
            echo -e "cURL output: $curl_content" >> "$LOG_FILE"

        release_tag=$(echo -e "$curl_content" | grep "tag_name" | cut -d \" -f 4)
        tarball_url=$(echo -e "$curl_content" | grep "tarball_url" | cut -d \" -f 4)
            log debug "selected tarball_url: \"$tarball_url\" with release_tag: \"$release_tag\""
        path_tarball="$CLI_TMP_WORKDIR/install_${APPLICATION_NAME}.tar.gz"
            log debug "selected path_tarball: \"$path_tarball\""

        if [ -n "tarball_url" ]; then
            spinner_toogle "Downloading latest version"
            # Download release
            curl --connect-timeout 10 -s -L "$tarball_url" -o "$path_tarball" >> "$LOG_FILE" 2>&1 || shutdown "Failed to connect or download tarball!"
            # Nasty check, if its a valid tar-file
            if [ "tar tf path_tarball &> /dev/null" ]; then
                if [ ! -d "$INSTALL_DIR" ]; then
                    mkdir "$INSTALL_DIR" || shutdown "Installation failed. REASON: could not create application directory \"$INSTALL_DIR\""
                else
                    ## TODO: define what to tidyup
                    rm -rf "$INSTALL_DIR"/*
                    rm -rf "$INSTALL_DIR"/.[!.]*
                fi
                ## TODO: Macos --strip 1 not avaialable
                # Extract tarball to INSTALL_DIR, note: stripping parent-folder containing commit-ID
                tar xfv "$path_tarball" --strip-components=1 -C "$INSTALL_DIR" >> "$LOG_FILE" 2>&1 || shutdown "Installation failed. REASON: could not extract tarball to \"$INSTALL_DIR\""

                # Execute common ansible playbook to prepare machine
                execute_ansible_playbook common
            else
                shutdown "Installation failed. REASON: could not download a valid tarball from \"$APPLICATION_GIT_API_URL\""
            fi

            spinner_toogle
        else
            shutdown "Installation failed: REASON: failed to fetch tarball_url for $release_url"
        fi

    else
        shutdown "Installation failed! REASON: cURL command not available"
    fi
}

#######################################
# Main
# Globals:
#   None
# Arguments:
#   Command
#   Subcommand
# Returns:
#   None
#######################################
function main {
    INIT_DEBUGLOG="Starting init routine, cmd line parameters are: \"$*\""
    init
    # Read cli parameters like -v for verbose and separately read arguments for ansible playbook
	while [[ $# -ge 0 ]]; do
	key="$1";case $key in

	## CLI params: -v -x -.... "command" "parameters"
	    -v|--verbose|--debug)
	        cli_enable_debug;shift;;
	    ""|-h|--help)
	        print_usage;shift;;
	    -*)
	        log error "ERROR: unkown CLI command line argument, aborting!";shutdown;;
	    # Todo trick temporary for install routine
	    install)
	        install_cli_itself;break;;
	    # Hand over parameters to execute_ansible_playbook function
	    *)
	        log debug "remaining positional parameters for ansible are: \"$*\"";
	        execute_ansible_playbook "$@";break;;
	esac;done

    print_footer
    shutdown
}

# start console tool with command line args
main "$@"
