FROM tweag/stack-docker-nix
MAINTAINER Felix Raimundo <felix.raimundo@tweag.io>

ADD shell.nix /
ADD nixpkgs.nix /
# Clean up non-essential downloaded archives after provisioning a shell.
RUN nix-shell /shell.nix --indirect --add-root /nix-shell-gc-root \
    && nix-collect-garbage
