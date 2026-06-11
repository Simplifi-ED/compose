class ContainerCompose < Formula
  desc "Apple Container CLI compose plugin"
  homepage "https://github.com/Simplifi-ED/compose"
  url "https://github.com/Simplifi-ED/compose/releases/download/v0.1.0/compose-plugin.tar.gz"
  # Replaced automatically by the release workflow before the first tap PR.
  sha256 "REPLACE_WITH_TARBALL_SHA256_HASH"
  license "Apache-2.0"

  depends_on macos: :sequoia
  depends_on arch: :arm64

  def install
    libexec.install "config.toml"
    (libexec/"bin").install "bin/compose"
  end

  def caveats
    <<~EOS
      To enable native discovery in apple/container, you must create a symlink
      to the plugin directory. Run the command matching your container install type:

      If you installed via Cask (brew install --cask container) or PKG:
        sudo mkdir -p /usr/local/libexec/container-plugins
        sudo ln -sf #{opt_libexec} /usr/local/libexec/container-plugins/compose

      If you installed via the experimental Homebrew formula:
        mkdir -p #{HOMEBREW_PREFIX}/opt/container/libexec/container-plugins
        ln -sf #{opt_libexec} #{HOMEBREW_PREFIX}/opt/container/libexec/container-plugins/compose

      Verify discovery with:
        container --help
    EOS
  end

  test do
    assert_match "compose", shell_output("#{opt_libexec}/bin/compose --help")
  end
end
