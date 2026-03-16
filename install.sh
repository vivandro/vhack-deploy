#!/usr/bin/env bash
set -euo pipefail

# install.sh — Install vhack-deploy on local machine

INSTALL_DIR="${HOME}/.vhack-deploy"
BIN_LINK="/usr/local/bin/vhack-deploy"

echo "Installing vhack-deploy..."

# Clone or update
if [[ -d "${INSTALL_DIR}" ]]; then
    echo "Updating existing installation..."
    cd "${INSTALL_DIR}"
    git pull origin main
else
    git clone https://github.com/vivandro/vhack-deploy.git "${INSTALL_DIR}"
fi

chmod +x "${INSTALL_DIR}/bin/vhack-deploy"

# Symlink to PATH
if [[ -L "${BIN_LINK}" ]] || [[ ! -e "${BIN_LINK}" ]]; then
    ln -sf "${INSTALL_DIR}/bin/vhack-deploy" "${BIN_LINK}"
    echo "Linked: ${BIN_LINK} → ${INSTALL_DIR}/bin/vhack-deploy"
else
    echo "Warning: ${BIN_LINK} already exists and is not a symlink."
    echo "Add ${INSTALL_DIR}/bin to your PATH manually."
fi

echo ""
echo "Done! Run 'vhack-deploy help' to get started."
