#!/usr/bin/env bash
# Checked with ShellCheck (https://www.shellcheck.net/)

#/ Generate and commit source files for Read The Docs.
#/
#/
#/ Arguments
#/ =========
#/
#/ --release
#/
#/   Build documentation sources intended for a Release build.
#/   If this option is not given, sources are built as development snapshots.
#/   Optional. Default: Disabled.



# Configure shell
# ===============

SELF_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd -P)"
source "$SELF_DIR/bash.conf.sh" || exit 1

log "==================== BEGIN ===================="
trap_add 'log "==================== END ===================="' EXIT

# Trace all commands (to stderr).
set -o xtrace



# Parse call arguments
# ====================

CFG_SSH_KEY_PATH=""
CFG_MAVEN_SETTINGS_PATH=""
CFG_RELEASE="false"

while [[ $# -gt 0 ]]; do
    case "${1-}" in
        --ssh-key)
            if [[ -n "${2-}" ]]; then
                CFG_SSH_KEY_PATH="$(realpath "$2")"
                shift
            else
                log "ERROR: --ssh-key expects <Path>"
                exit 1
            fi
            ;;
        --maven-settings)
            if [[ -n "${2-}" ]]; then
                CFG_MAVEN_SETTINGS_PATH="$(realpath "$2")"
                shift
            else
                log "ERROR: --maven-settings expects <Path>"
                exit 1
            fi
            ;;
        --release)
            CFG_RELEASE="true"
            ;;
        *)
            log "ERROR: Unknown argument '${1-}'"
            exit 1
            ;;
    esac
    shift
done



# Validate config
# ===============

log "CFG_SSH_KEY_PATH=$CFG_SSH_KEY_PATH"
log "CFG_MAVEN_SETTINGS_PATH=$CFG_MAVEN_SETTINGS_PATH"
log "CFG_RELEASE=$CFG_RELEASE"



# Generate doc
# ============

if [[ -n "${CFG_MAVEN_SETTINGS_PATH:-}" ]]; then
    sed "s|MAVEN_ARGS :=|MAVEN_ARGS := --settings $CFG_MAVEN_SETTINGS_PATH|" Makefile >Makefile.ci
else
    cp Makefile Makefile.ci
fi

make --file=Makefile.ci ci-readthedocs
rm Makefile.ci

if [[ "$CFG_RELEASE" == "true" ]]; then
    log "Command: kurento_check_version (tagging enabled)"
    kurento_check_version.sh --create-git-tag
else
    log "Command: kurento_check_version (tagging disabled)"
    kurento_check_version.sh
fi



# Commit generated doc
# ====================

if [[ -n "${CFG_SSH_KEY_PATH:-}" ]]; then
    # SSH is hardcoded to assume that the current UID is an already existing
    # system user. This was common in the past but not any more with containers.
    # Using the NSS wrapper library we can trick SSH into working with any UID.
    echo "kurento:x:$(id -u):$(id -g)::/home/kurento:/usr/sbin/nologin" >"/tmp/passwd"
    echo "kurento:x:$(id -g):" >"/tmp/group"
    # https://git-scm.com/docs/git#Documentation/git.txt-codeGITSSHCOMMANDcode
    export GIT_SSH_COMMAND="LD_PRELOAD=libnss_wrapper.so NSS_WRAPPER_PASSWD=/tmp/passwd NSS_WRAPPER_GROUP=/tmp/group ssh -i $CFG_SSH_KEY_PATH -o IdentitiesOnly=yes -o StrictHostKeychecking=no"
fi

REPO_NAME="doc-kurento-readthedocs"
REPO_URL="git@github.com:Kurento/$REPO_NAME.git"
REPO_DIR="$(mktemp --directory)"

git clone --depth 1 "$REPO_URL" "$REPO_DIR"

rsync -av --delete \
    --exclude-from=.gitignore \
    --exclude='.git*' \
    ./ "$REPO_DIR"/

log "Commit and push changes to Kurento/$REPO_NAME"

{
    pushd "$REPO_DIR"

    # Check if there are any changes; if so, commit them.
    if ! git diff-index --quiet HEAD; then
        # `--all` to include possibly deleted files.
        git add --all .

        git commit -m "Code autogenerated from Kurento/kurento@$GIT_HASH_SHORT"

        git push
    fi

    if [[ "$CFG_RELEASE" == "true" ]]; then
        log "Command: kurento_check_version (tagging enabled)"
        kurento_check_version.sh --create-git-tag
    else
        log "Command: kurento_check_version (tagging disabled)"
        kurento_check_version.sh
    fi

    popd  # $REPO_DIR
}
