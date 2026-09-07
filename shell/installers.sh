#!/usr/bin/env bash
# shell/installers.sh — workbench-gpg
# install-pinentry and its per-distro helpers. Ported from
# workbench-precursor's lazy/installers-dev.sh (the pinentry slice — that
# file split five ways across Wave C modules, per the module map's own §7
# call-out).
#
# WORKBENCH_OS/WORKBENCH_DISTRO are workbench-core Core API platform facts
# (contracts/core-api.md), replacing the precursor's DOTFILES_OS/DOTFILES_DISTRO.

# GPG's passphrase-entry helper. Without it, gpg-agent fails key generation
# and signing with "No pinentry". Common gap on minimal/WSL images. Installs
# a terminal-capable frontend (curses/tty) — no GUI/display dependency.

_pinentry-install-rhel() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    if command -v dnf &>/dev/null; then
        ${elevation_cmd} dnf install -y pinentry pinentry-tty
    else
        ${elevation_cmd} yum install -y pinentry pinentry-tty
    fi
}

_pinentry-install-debian() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    ${elevation_cmd} apt-get update
    ${elevation_cmd} apt-get install -y pinentry-curses
}

_pinentry-install-suse() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    ${elevation_cmd} zypper install -y pinentry
}

_pinentry-install-arch() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    ${elevation_cmd} pacman -S --noconfirm pinentry
}

_pinentry-install-mac() {
    command -v brew &>/dev/null || { log_error "brew is required on macOS"; return 1; }
    if command -v pinentry-mac &>/dev/null; then
        brew upgrade pinentry-mac 2>/dev/null || true
    else
        brew install pinentry-mac
    fi
}

# Some distros (Arch, macOS via Homebrew) install pinentry frontends without
# registering a generic `pinentry` binary via an alternatives system. Symlink
# the best available frontend into ~/.local/bin/pinentry so `command -v pinentry`
# resolves consistently everywhere, without touching system alternatives (root).
_pinentry_ensure_generic() {
    command -v pinentry &>/dev/null && return 0

    local candidate found=""
    for candidate in pinentry-tty pinentry-curses pinentry-gnome3 pinentry-qt pinentry-gtk-2 pinentry-mac; do
        if command -v "${candidate}" &>/dev/null; then
            found="$(command -v "${candidate}")"
            break
        fi
    done

    if [[ -z "${found}" ]]; then
        log_warn "pinentry: no frontend binary found after install"
        return 1
    fi

    mkdir -p "${HOME}/.local/bin"
    ln -sf "${found}" "${HOME}/.local/bin/pinentry"
    log_info "pinentry: linked $(basename "${found}") as ~/.local/bin/pinentry"

    if [[ ":${PATH}:" != *":${HOME}/.local/bin:"* ]]; then
        log_warn "${HOME}/.local/bin is not on PATH — add it in ~/.config/workbench/local/settings.sh"
    fi
}

install-pinentry() {
    log_info "Installing pinentry (GPG passphrase prompt)..."

    case "${WORKBENCH_OS}" in
        Mac) _pinentry-install-mac || return 1 ;;
        Linux)
            case "${WORKBENCH_DISTRO}" in
                rhel)   _pinentry-install-rhel   || return 1 ;;
                debian) _pinentry-install-debian || return 1 ;;
                suse)   _pinentry-install-suse   || return 1 ;;
                arch)   _pinentry-install-arch   || return 1 ;;
                *) log_error "pinentry: unknown distro (${WORKBENCH_DISTRO}) — install manually"; return 1 ;;
            esac
            ;;
        *) log_error "Unsupported OS for pinentry install"; return 1 ;;
    esac

    _pinentry_ensure_generic

    if command -v pinentry &>/dev/null; then
        log_info "pinentry installed: $(command -v pinentry)"
        [[ "${WORKBENCH_OS}" == "Mac" ]] && \
            log_info "macOS: set 'pinentry-program $(command -v pinentry-mac)' in ~/.gnupg/gpg-agent.conf for Touch ID / keychain prompts"
    else
        log_warn "pinentry not on PATH after install — check ~/.local/bin is in PATH"
        return 1
    fi
}
