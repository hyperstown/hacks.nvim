#!/usr/bin/env bash

if [ "$NVIM_INJECTION" == "1" ]; then
	if [ -z "$NVIM_SHELL_LOGIN" ]; then
		if [ -r ~/.bashrc ]; then
			. ~/.bashrc
		fi
	else
		# Imitate -l because --init-file doesn't support it:
		# run the first of these files that exists
		if [ -r /etc/profile ]; then
			. /etc/profile
		fi
		# execute the first that exists
		if [ -r ~/.bash_profile ]; then
			. ~/.bash_profile
		elif [ -r ~/.bash_login ]; then
			. ~/.bash_login
		elif [ -r ~/.profile ]; then
			. ~/.profile
		fi
		builtin unset NVIM_SHELL_LOGIN

		# Apply any explicit path prefix (see #99878)
		if [ -n "${NVIM_PATH_PREFIX:-}" ]; then
			export PATH="$NVIM_PATH_PREFIX$PATH"
			builtin unset NVIM_PATH_PREFIX
		fi
	fi
	builtin unset NVIM_INJECTION
else
	echo "MUH!"
fi

# Escape command string for OSC
__nvim_escape_value() {
    local str="$1"
    str="${str//\\/\\\\}"  # escape backslashes
    str="${str//;/\\;}"    # escape semicolons
    str="${str//$'\n'/\\n}" # escape newlines
    echo "$str"
}

# Emit OSC 633;P for current directory
__nvim_emit_cwd() {
    local cwd="$PWD"
    printf '\033]633;P;Cwd=%s\a' "$cwd"
}

# Emit OSC 633;E for the command that is about to run
__nvim_command_output_start() {
    local cmd="$BASH_COMMAND"
    printf '\033]633;E;%s\a' "$(__nvim_escape_value "$cmd")"
}

# Hook for preexec — command about to execute
trap '__nvim_command_output_start' DEBUG

# Hook for PROMPT_COMMAND — after each command finishes
PROMPT_COMMAND='__nvim_emit_cwd'
