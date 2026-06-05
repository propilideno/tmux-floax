#!/usr/bin/env bash

envvar_value() {
    tmux showenv -g "$1" | cut -d '=' -f 2-
}

tmux_option_or_fallback() {
	local option_value
	option_value="$(tmux show-option -gqv "$1")"
	if [ -z "$option_value" ]; then
		option_value="$2"
	fi
	echo "$option_value"
}

FLOAX_WIDTH=$(envvar_value FLOAX_WIDTH)
FLOAX_HEIGHT=$(envvar_value FLOAX_HEIGHT)
FLOAX_BORDER_COLOR=$(envvar_value FLOAX_BORDER_COLOR)
FLOAX_TEXT_COLOR=$(envvar_value FLOAX_TEXT_COLOR)
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOAX_CHANGE_PATH=$(envvar_value FLOAX_CHANGE_PATH)
FLOAX_TITLE=$(envvar_value FLOAX_TITLE)
FLOAX_HIDE_TITLE=$(envvar_value FLOAX_HIDE_TITLE)
FLOAX_CLIPBOARD=$(envvar_value FLOAX_CLIPBOARD)
DEFAULT_TITLE='FloaX: C-M-s 󰘕   C-M-b 󰁌   C-M-f 󰊓   C-M-r 󰑓   C-M-e 󱂬   C-M-d '
FLOAX_SESSION_NAME=$(envvar_value FLOAX_SESSION_NAME)
DEFAULT_SESSION_NAME='scratch'

# Detect a system clipboard command available on the tmux server host.
# tmux popups do not forward OSC 52 clipboard escape sequences to the real
# terminal, so copying inside the floating pane silently fails. Piping the
# selection straight to a clipboard utility via copy-pipe sidesteps OSC 52
# entirely, since the command runs on the server rather than relying on
# escape-sequence passthrough.
detect_clipboard_command() {
    if command -v pbcopy >/dev/null 2>&1; then
        echo "pbcopy"
    elif [ -n "$WAYLAND_DISPLAY" ] && command -v wl-copy >/dev/null 2>&1; then
        echo "wl-copy"
    elif command -v xclip >/dev/null 2>&1; then
        echo "xclip -selection clipboard -in"
    elif command -v xsel >/dev/null 2>&1; then
        echo "xsel --clipboard --input"
    elif command -v clip.exe >/dev/null 2>&1; then
        echo "clip.exe"
    fi
}

# Wire copy-mode yanks to the system clipboard so copying works inside the
# floating popup. Honors @floax-clipboard:
#   on/auto (default) - detect a clipboard tool and pipe selections to it
#   off               - leave the user's copy-mode bindings untouched
#   <command>         - use the given command as the clipboard target
setup_clipboard() {
    local mode="$FLOAX_CLIPBOARD"
    if [ -z "$mode" ]; then
        mode="on"
    fi
    if [ "$mode" = "off" ] || [ "$mode" = "false" ]; then
        return
    fi

    # Enable OSC 52 too; harmless and helps terminals that do support it.
    tmux set-option -g set-clipboard on

    local clipboard_command
    case "$mode" in
        on|auto|true)
            clipboard_command="$(detect_clipboard_command)"
            ;;
        *)
            clipboard_command="$mode"
            ;;
    esac

    if [ -z "$clipboard_command" ]; then
        return
    fi

    local table
    for table in copy-mode copy-mode-vi; do
        tmux bind-key -T "$table" Enter \
            send-keys -X copy-pipe-and-cancel "$clipboard_command"
        tmux bind-key -T "$table" MouseDragEnd1Pane \
            send-keys -X copy-pipe-and-cancel "$clipboard_command"
    done
    # vi-style yank key
    tmux bind-key -T copy-mode-vi y \
        send-keys -X copy-pipe-and-cancel "$clipboard_command"
}

set_bindings() {
    tmux bind -n C-M-s run "$CURRENT_DIR/zoom-options.sh in"
    tmux bind -n c-M-b run "$CURRENT_DIR/zoom-options.sh out"
    tmux bind -n C-M-f run "$CURRENT_DIR/zoom-options.sh full"
    tmux bind -n C-M-r run "$CURRENT_DIR/zoom-options.sh reset"
    tmux bind -n C-M-e run "$CURRENT_DIR/embed.sh embed"
    tmux bind -n C-M-d run "$CURRENT_DIR/zoom-options.sh lock" 
    tmux bind -n C-M-u run "$CURRENT_DIR/zoom-options.sh unlock"
}

unset_bindings() {
    tmux unbind -n C-M-s
    tmux unbind -n C-M-b
    tmux unbind -n C-M-f 
    tmux unbind -n C-M-r 
    tmux unbind -n C-M-e 
    tmux unbind -n C-M-d 
    tmux unbind -n C-M-u 
}

tmux_version() {
  tmux -V | cut -d ' ' -f 2 | sed 's/[^0-9.]//g'
}

# Checks whether tmux version is >= 3.3
is_tmux_version_supported() {
    local version
    IFS='.' read -r -a version < <(tmux_version)

    if [ "${version[0]}" -gt 3 ]; then
        return 0
    fi

    # Minor version can be a number or alphanumeric, e.g. 3.3 vs 3.3a
    if [ "${version[0]}" -eq 3 ] && [ "${version[1]//[!0-9]}" -ge 3 ]; then
        return 0
    fi

    return 1
}

tmux_popup() {
    if [ -z "$FLOAX_SESSION_NAME" ]; then
        FLOAX_SESSION_NAME="$DEFAULT_SESSION_NAME"
    fi

    setup_clipboard
    # TODO: make this optional:
    current_dir=$(tmux display -p '#{pane_current_path}')
    scratch_path=$(tmux display -t "$FLOAX_SESSION_NAME" -p '#{pane_current_path}')
    if [ "$scratch_path" != "$current_dir" ] && [ "$FLOAX_CHANGE_PATH" = "true" ]; then
        tmux send-keys -R -t "$FLOAX_SESSION_NAME" " cd \"$current_dir\"" C-m
    fi

    if is_tmux_version_supported; then
        if ! pop; then
            tmux setenv -g FLOAX_WIDTH "$(tmux_option_or_fallback '@floax-width' '80%')" 
            tmux setenv -g FLOAX_HEIGHT "$(tmux_option_or_fallback '@floax-height' '80%')"
            pop
        fi
    else
        tmux display-message \
            -d 2000 \
            "FloaX requires tmux version 3.3 or newer"
    fi
}

pop() {
    FLOAX_WIDTH=$(envvar_value FLOAX_WIDTH)
    FLOAX_HEIGHT=$(envvar_value FLOAX_HEIGHT)
    FLOAX_HIDE_TITLE=$(envvar_value FLOAX_HIDE_TITLE)

    FLOAX_TITLE=$(envvar_value FLOAX_TITLE)
    if [ -z "$FLOAX_TITLE" ]; then
        FLOAX_TITLE="$DEFAULT_TITLE"
    fi

    FLOAX_SESSION_NAME=$(envvar_value FLOAX_SESSION_NAME)
    if [ -z "$FLOAX_SESSION_NAME" ]; then
        FLOAX_SESSION_NAME="$DEFAULT_SESSION_NAME"
    fi

    tmux set-option -t "$FLOAX_SESSION_NAME" detach-on-destroy on
    local popup_args=(
        -S "fg=$FLOAX_BORDER_COLOR"
        -s "fg=$FLOAX_TEXT_COLOR"
        -w "$FLOAX_WIDTH"
        -h "$FLOAX_HEIGHT"
        -b rounded
        -E
    )
    if [ "$FLOAX_HIDE_TITLE" != "true" ]; then
        popup_args+=(-T "$FLOAX_TITLE")
    else
        tmux set-window-option -t "$FLOAX_SESSION_NAME" pane-border-status off
    fi
    tmux popup "${popup_args[@]}" "tmux attach-session -t \"$FLOAX_SESSION_NAME\""
}
