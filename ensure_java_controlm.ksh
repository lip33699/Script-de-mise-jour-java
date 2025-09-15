#!/bin/ksh
# ==================================================================
# Script : ensure_java_controlm.ksh
# Purpose : Ensure / Install Java 11 required by Control-M Agent
#           version 9.0.21.300 on AIX and Linux (RHEL 7/8/9).
# ==================================================================

# ------------------------------------------------------------------
# Global variable: expected Java version
# Control-M 9.0.21.300 requires Java 11 (BMC recommends Semeru/OpenJDK 11).
# ------------------------------------------------------------------
CTM_JAVA_VERSION=11

# ------------------------------------------------------------------
# Function log: print a message with timestamp (for debugging).
# ------------------------------------------------------------------
log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

# ------------------------------------------------------------------
# Function die: print an error and stop the script.
# ------------------------------------------------------------------
die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

# ------------------------------------------------------------------
# Function detect_os: detect the operating system (AIX or Linux).
# ------------------------------------------------------------------
detect_os() {
  OS_NAME="$(uname -s 2>/dev/null)"
  case "$OS_NAME" in
    Linux) echo "Linux";;
    AIX)   echo "AIX";;
    *)     die "Unsupported OS: ${OS_NAME:-unknown}";;
  esac
}

# ------------------------------------------------------------------
# Function install_java_linux:
# Install Java 11 on Linux Red Hat (via yum or dnf).
# Then determine automatically JAVA_HOME.
# ------------------------------------------------------------------
install_java_linux() {
  log "Linux detected → installing OpenJDK ${CTM_JAVA_VERSION}"

  if command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y "java-${CTM_JAVA_VERSION}-openjdk" || \
    sudo dnf install -y "java-${CTM_JAVA_VERSION}-openjdk-headless"
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y "java-${CTM_JAVA_VERSION}-openjdk" || \
    sudo yum install -y "java-${CTM_JAVA_VERSION}-openjdk-headless"
  else
    die "Neither yum nor dnf found. Please install OpenJDK ${CTM_JAVA_VERSION} manually."
  fi

  # Automatically resolve JAVA_HOME from java binary
  JAVABIN="$(command -v java)"
  REALBIN="$(readlink -f "$JAVABIN" 2>/dev/null || echo "$JAVABIN")"
  export BMC_INST_JAVA_HOME="$(dirname "$(dirname "$REALBIN")")"
  log "Java installed at $BMC_INST_JAVA_HOME"
}

# ------------------------------------------------------------------
# Function install_java_aix:
# Check if Java 11 is present at /usr/java11_64.
# If not, try installation via installp from $AIX_JAVA_FILES_DIR
# (must point to an NFS/NIM directory with IBM Semeru images).
# ------------------------------------------------------------------
install_java_aix() {
  log "AIX detected → required Java is IBM Semeru 11 (64-bit)"

  if [ -x /usr/java11_64/bin/java ]; then
    export BMC_INST_JAVA_HOME="/usr/java11_64"
    log "Java 11 already present at $BMC_INST_JAVA_HOME"
    return
  fi

  if [ -n "${AIX_JAVA_FILES_DIR:-}" ] && [ -d "${AIX_JAVA_FILES_DIR}" ]; then
    log "Installing Java 11 from $AIX_JAVA_FILES_DIR ..."
    sudo installp -aY -d "${AIX_JAVA_FILES_DIR}" all || die "installp failed"
    [ -x /usr/java11_64/bin/java ] || die "Java 11 not found after installp"
    export BMC_INST_JAVA_HOME="/usr/java11_64"
    log "Java 11 installed at $BMC_INST_JAVA_HOME"
  else
    die "Java 11 not available. Set AIX_JAVA_FILES_DIR or install IBM Semeru manually."
  fi
}

# ------------------------------------------------------------------
# Function validate_java:
# Check that Java is present and its version is 11.x
# ------------------------------------------------------------------
validate_java() {
  [ -x "${BMC_INST_JAVA_HOME}/bin/java" ] || die "Java binary missing in $BMC_INST_JAVA_HOME"
  ver="$("${BMC_INST_JAVA_HOME}/bin/java" -version 2>&1 | head -1)"
  echo "$ver" | grep 'version "11\.' >/dev/null 2>&1 || die "Unsupported version ($ver). Java 11 required."
  log "Java validated: $ver"
}

# ------------------------------------------------------------------
# MAIN : main script execution
# ------------------------------------------------------------------
OS=$(detect_os)

case $OS in
  Linux) install_java_linux ;;
  AIX)   install_java_aix ;;
esac

validate_java

echo "BMC_INST_JAVA_HOME=${BMC_INST_JAVA_HOME}"
