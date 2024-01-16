# shellcheck shell=sh disable=SC2166,SC2157,SC3044

# Check for interactive bash
if [ "x${BASH_VERSION-}" != x -a "x${PS1-}" ]; then
  ADMIN_CONF=/etc/kubernetes/admin.conf
  SUPER_ADMIN_CONF=/etc/kubernetes/super-admin.conf

  if [ -r "${SUPER_ADMIN_CONF}" ]; then
    export KUBECONFIG="${SUPER_ADMIN_CONF}"
  elif [ -r "${ADMIN_CONF}" ]; then
    export KUBECONFIG="${ADMIN_CONF}"
  fi

  alias k=kubectl
  __load_completion kubectl >/dev/null 2>&1 || true
  complete -F __start_kubectl k 2>/dev/null || true
fi
