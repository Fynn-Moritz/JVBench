#!/usr/bin/env bash
#
# setup.sh - Prepares a fresh Linux machine (aarch64 or x86_64) for JVBench:
# installs tools, Maven and Amazon Corretto 19 and 27, sets environment
# variables, clones the repository and builds one JAR per JDK.
#
# Usage:
#   REPO_URL=https://github.com/Fynn-Moritz/JVBench.git bash setup.sh
#
# Safe to run more than once: existing downloads, installations and the
# repository are reused. Checksums of all downloads are written to
# ~/setup_checksums.txt for documentation.

set -euo pipefail

REPO_URL="${REPO_URL:?Please set REPO_URL, e.g. https://github.com/Fynn-Moritz/JVBench.git}"
REPO_DIR="${REPO_DIR:-$HOME/JVBench}"
MAVEN_VERSION="${MAVEN_VERSION:-3.10.0}"
CORRETTO19="${CORRETTO19:-19.0.2.7.1}"
CORRETTO27="${CORRETTO27:-27.0.0.35.1}"
CHECKSUMS="$HOME/setup_checksums.txt"

case "$(uname -m)" in
  aarch64) ARCH=aarch64 ;;
  x86_64)  ARCH=x64 ;;
  *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

echo "== Installing packages"
if command -v dnf >/dev/null 2>&1; then
  # curl is not installed explicitly: Amazon Linux 2023 ships curl-minimal
  sudo dnf install -y git tar gzip unzip tmux util-linux
elif command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y git tar gzip unzip tmux util-linux curl
else
  echo "No supported package manager (dnf or apt-get) found"; exit 1
fi

# Download a tarball (if needed), log its checksum, extract it to /opt
# and point a short symlink /opt/<link> at it.
install_tarball() {
  local url="$1" dir="$2" link="$3"
  local file="/tmp/$(basename "$url")"
  if [[ ! -d "/opt/$dir" ]]; then
    [[ -f "$file" ]] || curl -fL -o "$file" "$url"
    sha256sum "$file" | tee -a "$CHECKSUMS"
    sudo tar -xzf "$file" -C /opt
  fi
  [[ -d "/opt/$dir" ]] || { echo "Expected /opt/$dir after extracting $file"; exit 1; }
  sudo ln -sfn "/opt/$dir" "/opt/$link"
  echo "/opt/$link -> /opt/$dir"
}

echo "== Installing Maven and Corretto"
install_tarball \
  "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
  "apache-maven-${MAVEN_VERSION}" "maven"
install_tarball \
  "https://corretto.aws/downloads/resources/${CORRETTO19}/amazon-corretto-${CORRETTO19}-linux-${ARCH}.tar.gz" \
  "amazon-corretto-${CORRETTO19}-linux-${ARCH}" "jdk-19"
install_tarball \
  "https://corretto.aws/downloads/resources/${CORRETTO27}/amazon-corretto-${CORRETTO27}-linux-${ARCH}.tar.gz" \
  "amazon-corretto-${CORRETTO27}-linux-${ARCH}" "jdk-27"

echo "== Environment"
if ! grep -q '# --- JVBench setup ---' "$HOME/.bashrc"; then
  cat >> "$HOME/.bashrc" <<'EOF'

# --- JVBench setup ---
export JDK19_HOME=/opt/jdk-19
export JDK27_HOME=/opt/jdk-27
export JAVA_HOME=$JDK27_HOME
export MAVEN_HOME=/opt/maven
export PATH="$JAVA_HOME/bin:$MAVEN_HOME/bin:$PATH"
EOF
  echo "Added JVBench block to ~/.bashrc"
else
  echo "~/.bashrc already contains the JVBench block"
fi
export JDK19_HOME=/opt/jdk-19 JDK27_HOME=/opt/jdk-27 MAVEN_HOME=/opt/maven
export PATH="$MAVEN_HOME/bin:$PATH"

echo "== Repository"
if [[ -d "$REPO_DIR/.git" ]]; then
  git -C "$REPO_DIR" pull --ff-only
else
  git clone "$REPO_URL" "$REPO_DIR"
fi
cd "$REPO_DIR"

echo "== Building one JAR per JDK"
mkdir -p jars
for v in 27 19; do
  home_var="JDK${v}_HOME"
  JAVA_HOME="${!home_var}" mvn -B -q clean package
  cp target/JVBench-2.0.0.jar "jars/JVBench-jdk${v}.jar"
  spec="$(unzip -p "jars/JVBench-jdk${v}.jar" META-INF/MANIFEST.MF | tr -d '\r' | grep Build-Jdk-Spec || true)"
  echo "jars/JVBench-jdk${v}.jar  ($spec)"
done

echo "== Summary"
"$JDK19_HOME/bin/java" -version 2>&1 | head -1
"$JDK27_HOME/bin/java" -version 2>&1 | head -1
mvn -version 2>&1 | head -1
"$JDK27_HOME/bin/java" --add-modules jdk.incubator.vector tools/SpeciesInfo.java 2>/dev/null || true
echo
echo "Done. Open a new shell (or run 'source ~/.bashrc'), then e.g.:"
echo "  cd $REPO_DIR && DRYRUN=1 bash run_all.sh"
