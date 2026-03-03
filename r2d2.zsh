# Thin Zsh wrapper for the standalone bash implementation.

typeset -g _R2D2_PACKAGE_DIR="${${(%):-%N}:A:h}"

r2d2() {
  if ! command -v bash >/dev/null 2>&1; then
    print -u2 -- "r2d2: bash is required"
    return 1
  fi

  command bash "$_R2D2_PACKAGE_DIR/r2d2.sh" "$@"
}
