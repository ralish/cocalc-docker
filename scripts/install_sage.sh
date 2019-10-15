#!/usr/bin/env bash

# Wrapper script for handling Sage compilation under Docker

# A better class of script...
set -o errexit          # Exit on most errors (see the manual)
set -o errtrace         # Make sure any error trap is inherited
set -o nounset          # Disallow expansion of unset variables
set -o pipefail         # Use last non-zero exit code in a pipeline
#set -o xtrace          # Trace the execution of the script (debug)

# Default settings
readonly SAGE_SRC_BRANCH_DEFAULT='master'
readonly SAGE_SRC_REPO_DEFAULT='https://github.com/sagemath/sage.git'
readonly SAGE_SRC_TARGET_DEFAULT='/usr/local'
readonly SAGE_USER_DEFAULT='sage'

# Can be overridden at runtime
SAGE_SRC_BRANCH="$SAGE_SRC_BRANCH_DEFAULT"
SAGE_SRC_REPO="$SAGE_SRC_REPO_DEFAULT"
SAGE_SRC_TARGET="$SAGE_SRC_TARGET_DEFAULT"
SAGE_USER="$SAGE_USER_DEFAULT"

# DESC: Usage help
# ARGS: None
# OUTS: None
function script_usage() {
    local script_usage

    script_usage="Usage:
     -h|--help                  Displays this help
     -v|--verbose               Displays verbose output
    -nc|--no-colour             Disables colour output
     -f|--force                 Skip various sanity checks

Install mode (multiple permitted):
     -i|--install               Build & install Sage
     -p|--post-install          Post-install steps

Shared parameters:
     -u|--sage-user             User for Sage installation
                                Default: $SAGE_USER_DEFAULT

Installation parameters:
     -r|--sage-src-repo         URL of Sage repository (must be named \"sage\")
                                Default: $SAGE_SRC_REPO_DEFAULT
     -b|--sage-src-branch       Sage branch to checkout
                                Default: $SAGE_SRC_BRANCH_DEFAULT
     -t|--sage-src-target       Target path for Sage
                                Default: $SAGE_SRC_TARGET_DEFAULT
     --[no]-clean               Clean-up intermediate build outputs
                                Default: Enabled unless branch is \"develop\""

    printf '%s\n' "$script_usage"
}


# DESC: Parameter parser
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: Variables indicating command-line parameters and options
function parse_params() {
    local param
    while [[ $# -gt 0 ]]; do
        param="$1"
        shift
        case $param in
            -h|--help)
                script_usage
                exit 0
                ;;
            -v|--verbose)
                verbose=true
                ;;
            -nc|--no-colour)
                no_colour=true
                ;;
            -i|--install)
                sage_install=true
                ;;
            -p|--post-install)
                sage_postinstall=true
                ;;
            -r|--sage-src-repo)
                if [[ -z ${1-} ]]; then
                    script_exit 'No Sage repository URL provided.' 1
                fi
                SAGE_SRC_REPO="$1"
                shift
                ;;
            -b|--sage-src-branch)
                if [[ -z ${1-} ]]; then
                    script_exit 'No Sage checkout branch provided.' 1
                fi
                SAGE_SRC_BRANCH="$1"
                shift
                ;;
            -t|--sage-src-target)
                if [[ -z ${1-} ]]; then
                    script_exit 'No Sage target path provided.' 1
                fi
                SAGE_SRC_TARGET="${1%/}"
                shift
                ;;
            -u|--sage-user)
                if [[ -z ${1-} ]]; then
                    script_exit 'No Sage user account provided.' 1
                fi
                SAGE_USER="$1"
                shift
                ;;
            --clean)
                clean=true
                ;;
            --no-clean)
                clean=false
                ;;
            -f|--force)
                force=true
                ;;
            *)
                script_exit "Invalid parameter was provided: $param" 2
                ;;
        esac
    done

    if [[ -z ${sage_install-} && -z ${sage_postinstall-} ]]; then
        script_exit 'At least one installation mode must be specified.' 1
    fi

    if [[ ! -d $SAGE_SRC_TARGET ]]; then
        script_exit 'Target path for the Sage source is not a directory.' 1
    fi

    if ! id "$SAGE_USER" > /dev/null 2>&1; then
        script_exit 'Specified user account for Sage does not exist.' 1
    fi

    if [[ -z ${clean-} ]]; then
        if [[ $SAGE_SRC_BRANCH != 'develop' ]]; then
            clean=true
        else
            clean=false
        fi
    fi

    if [[ $EUID -ne 0 && -z ${force-} ]]; then
        script_exit 'Expecting to run as root (override with --force).' 1
    fi
}


# DESC: Build & install Sage
# ARGS: None
# OUTS: None
function sage_install() {
    pretty_print 'Running Sage build & install ...'

    # Clone the Sage repository
    pretty_print 'Cloning Sage repository ...'
    cd "$SAGE_SRC_TARGET"
    git clone --depth 1 --branch "$SAGE_SRC_BRANCH" "$SAGE_SRC_REPO"

    # Update user/group ownership
    pretty_print 'Updating user/group ownership ...'
    chown -R sage:"$(id -gn "$SAGE_USER")" sage
    cd sage

    # If the MAKE environment variable isn't already defined we'll set it to
    # run as many jobs as there are CPU cores. This will dramatically speed-up
    # the build on modern systems.
    if [[ -z ${MAKE-} ]]; then
        local nproc
        nproc="$(nproc)"
        export MAKE="make -j$nproc"
        pretty_print "Setting MAKE env var to: $MAKE"
    else
        pretty_print "Using parameters from MAKE env var: $MAKE"
    fi

    # Sage can't be built as root so we must run the build in the context of
    # the specified Sage user account. The sudo parameters are essential:
    #
    # -H: Set HOME to the target user's home directory. Not doing so will use
    #     the invoking user's home directory, causing all manner of breakage.
    # -E: Inherit the invoking user's environment. Important so that the MAKE
    #     environment variable is preserved, alongside others which influence
    #     the Sage build.
    #     See: https://doc.sagemath.org/html/en/installation/source.html#id10
    pretty_print 'Building Sage (this is going to take a while) ...'
    sudo -H -E -u "$SAGE_USER" make

    # Create symlinks to the sage binary
    pretty_print 'Creating Sage symlinks ...'
    ln -sf "$SAGE_SRC_TARGET/sage/sage" /usr/local/bin/sage
    ln -sf "$SAGE_SRC_TARGET/sage/sage" /usr/local/bin/sagemath

    # Perform some clean-up of intermediate outputs from the build process
    if [[ $clean == 'true' ]]; then
        pretty_print 'Removing intermediate Sage build outputs ...'
        make misc-clean
        make -C src/ clean
        rm -rf upstream/

        # Strip binaries
        pretty_print 'Stripping Sage binaries ...'
        LC_ALL=C find local/bin local/lib -type f -exec strip '{}' ';' 2>&1 | grep -Ev 'File (format not recognized|truncated)' || true
    fi
}


# DESC: Post-install steps
# ARGS: None
# OUTS: None
function sage_postinstall() {
    pretty_print 'Running Sage post-install steps ...'

    # Create scripts in /usr/local/bin to sage binaries
    pretty_print 'Creating Sage scripts in /usr/local/bin ...'
    sage --nodotsage -c "install_scripts('/usr/local/bin')"

    # Set admin password for legacy Sage notebook
    pretty_print 'Setting admin password for legacy Sage notebook ...'
    sudo -H -u "$SAGE_USER" sage << EOF
        from sage.misc.misc import DOT_SAGE
        from sagenb.notebook import notebook
        directory = DOT_SAGE + 'sage_notebook'
        nb = notebook.load_notebook(directory)
        nb.user_manager().add_user('admin', 'sage', '', force=True)
        nb.save()
        quit
EOF

    # Install SageTex
    pretty_print 'Installing SageTex ...'
    sudo -H -u "$SAGE_USER" sage -p sagetex
    ln -sf "$SAGE_SRC_TARGET/sage/local/share/texmf/tex/latex/sagetex" /usr/share/texmf/tex/latex
    texhash

    # Install R Jupyter Kernel
    local r_install_jupyter_kernel
    r_install_jupyter_kernel="install.packages(c('repr', 'IRdisplay', 'evaluate', 'crayon', 'pbdZMQ', 'httr', 'devtools', 'uuid', 'digest'), repos='http://cran.us.r-project.org'); devtools::install_github('IRkernel/IRkernel')"
    pretty_print 'Installing Jupyter Kernel into R (Sage version) ...'
    echo "$r_install_jupyter_kernel" | sage -R --no-save
    pretty_print 'Installing Jupyter Kernel into R (system version) ...'
    echo "$r_install_jupyter_kernel" | R --no-save
}


# DESC: Main control flow
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: None
function main() {
    # shellcheck source=scripts/template.sh
    source "$(dirname "${BASH_SOURCE[0]}")/template.sh"

    trap script_trap_err ERR
    trap script_trap_exit EXIT

    script_init "$@"
    parse_params "$@"
    colour_init

    check_binary sudo fatal

    if [[ -n ${sage_install-} ]]; then
        check_binary git fatal
        check_binary make fatal
        sage_install
    fi

    if [[ -n ${sage_postinstall-} ]]; then
        check_binary sage fatal
        sage_postinstall
    fi
}


main "$@"
