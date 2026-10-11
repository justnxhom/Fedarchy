#!/bin/bash
# Fedarchy component model.
#
# One source of truth for what can be installed, what each part does, what it
# depends on, and which files it touches. The wizard, the plan builder, the
# --check diagnostics and the tests all read these definitions, so the list
# cannot drift between the interface and what actually happens.
#
# Every component here corresponds to files that exist in this tree and to a
# destination the runtime genuinely reads. Nothing is listed for effect: the
# rationale is that advertising a component which does not do anything is worse
# than not advertising it at all.
#
# Fields, one per line, pipe-separated:
#   id | required | depends-on | destination | description | why-you-might-want-it
#
# `required` is 1 for parts with no working substitute. `depends-on` lists
# component ids that must also be selected; a selection is expanded to include
# them before the plan is rendered, so the user never has to resolve a
# dependency by hand.

# Components, in the order the wizard presents them. Order is deliberate:
# required core first, then appearance, then optional integrations.
COMPONENT_SPECS=(
    "shell|1||OMARCHY_PATH|The desktop shell, its runtime resources and helper modules|Everything Fedarchy does at the bar, panels and overlays runs from this"
    "commands|1||~/.local/bin|The omarchy commands you type|Run 'omarchy shell ping' or any omarchy-* helper from a terminal"
    "themes|0||~/.config/omarchy/themes|The full theme collection|Switch appearance instantly with omarchy-theme-set"
    "hypr-config|0|shell|~/.config/hypr|Fedarchy's Hyprland configuration, including window behaviour and layout|Sensible window management and monitors out of the box"
    "keybindings|0|hypr-config|~/.config/hypr|Fedarchy's keyboard shortcuts|Move between workspaces and run actions without touching the mouse"
    "app-configs|0|shell|~/.config|Ready-made configuration for terminals, browsers and other apps|Working defaults for the tools you already use"
    "bar-widgets|0|shell|~/.config/omarchy/shell.json|Which widgets appear on the bar|Keep the bar minimal, or match a fuller layout"
)

component_field() {
    local id="$1" index="$2"
    local spec
    for spec in "${COMPONENT_SPECS[@]}"; do
        [[ ${spec%%|*} == "$id" ]] || continue
        printf '%s\n' "${spec}" | cut -d'|' -f"$index"
        return 0
    done
    return 1
}

component_exists() {
    local spec
    for spec in "${COMPONENT_SPECS[@]}"; do
        [[ ${spec%%|*} == "$1" ]] && return 0
    done
    return 1
}

component_ids() {
    local spec
    for spec in "${COMPONENT_SPECS[@]}"; do printf '%s\n' "${spec%%|*}"; done
}

component_required() { [[ $(component_field "$1" 2) == 1 ]]; }
component_depends() { component_field "$1" 3; }
component_dest() { component_field "$1" 4; }
component_desc() { component_field "$1" 5; }
component_why() { component_field "$1" 6; }

# Human-facing name. Derived from the id so there is no second list to keep
# in sync, with the common acronyms spelled the way a user would recognise.
component_label() {
    case "$1" in
        hypr-config) printf 'Hyprland configuration' ;;
        keybindings) printf 'Keyboard shortcuts' ;;
        app-configs) printf 'Application configuration' ;;
        bar-widgets) printf 'Bar widgets' ;;
        commands) printf 'Command-line tools' ;;
        *) printf '%s\n' "${1//-/ }" | sed 's/^./\U&/' ;;
    esac
}

# --- Selection resolution ---------------------------------------------------

# Expands a selection to include every transitive dependency and every
# required component. Output follows the declared component order so plans and
# prompts stay stable between runs.
resolve_dependencies() {
    local -A included=()
    local queue=("$@")
    local id spec dep

    while ((${#queue[@]})); do
        id="${queue[0]}"
        queue=("${queue[@]:1}")
        [[ -n $id ]] || continue
        component_exists "$id" || continue
        [[ -n ${included[$id]:-} ]] && continue
        :
        included[$id]=1
        dep=$(component_depends "$id") || dep=""
        [[ -n $dep ]] && queue+=("$dep")
    done

    # Required components come along whether or not anyone asked for them.
    for spec in "${COMPONENT_SPECS[@]}"; do
        id="${spec%%|*}"
        component_required "$id" && included[$id]=1 || true
    done

    for spec in "${COMPONENT_SPECS[@]}"; do
        id="${spec%%|*}"
        if [[ -n ${included[$id]:-} ]]; then printf '%s\n' "$id"; fi
    done
}

# Profiles. Each is a starting point the user may edit before installing;
# nothing here is applied without the final review and confirmation.
profile_components() {
    case "$1" in
        minimal)   printf '%s\n' shell commands themes ;;
        recommended) printf '%s\n' shell commands themes hypr-config keybindings bar-widgets ;;
        preserve)  printf '%s\n' shell commands themes app-configs ;;
        *)         return 1 ;;
    esac
}

# Components that were left out, and why that matters. Shown in the plan so a
# user can see what they are not getting, not only what they are.
component_skipped_note() {
    case "$1" in
        keybindings)
            printf 'Fedarchy keyboard shortcuts are not applied; your existing ones stay in effect.' ;;
        hypr-config)
            printf 'Fedarchy Hyprland configuration is not applied; your Hyprland setup is untouched.' ;;
        themes)
            printf 'No themes are installed; your existing appearance resources are left alone.' ;;
        app-configs)
            printf 'No application configuration templates are applied.' ;;
        bar-widgets)
            printf 'The bar layout is not changed by this installation.' ;;
        *) return 0 ;;
    esac
}