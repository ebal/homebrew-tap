class Lilyterm < Formula
  desc "Light and easy to use libvte based terminal emulator"
  homepage "https://github.com/ebal/LilyTerm"
  url "https://github.com/ebal/LilyTerm/archive/refs/tags/v0.14.0.tar.gz"
  sha256 "2f679fa84c9d098070cb816e38cff27be2715d323c3abf7e2bd7c319e498aace"
  license "GPL-3.0-or-later"
  head "https://github.com/ebal/LilyTerm.git", branch: "main"

  depends_on "pkgconf" => :build
  depends_on "at-spi2-core"
  depends_on "cairo"
  depends_on "gdk-pixbuf"
  depends_on "gettext"
  depends_on "glib"
  depends_on "gtk+3"
  depends_on "harfbuzz"
  depends_on "pango"
  depends_on "vte3"

  def install
    system "./configure", "--prefix=#{prefix}",
                          "--sysconfdir=#{etc}/xdg",
                          "--disable-gnome-control-center"
    system "make"
    system "make", "install"
  end

  def caveats
    <<~EOS
      LilyTerm runs with the native macOS (Quartz) backend of GTK+ 3.
      Start it from a terminal:
        lilyterm

      Window transparency is off on macOS, because GTK+ 3 then draws the
      title bar clear as well. To turn it on anyway, set use_rgba = 1 in
      ~/.config/lilyterm/default.conf.

      The system wide settings are in:
        #{etc}/xdg/lilyterm.conf
    EOS
  end

  test do
    assert_match(/^LilyTerm \d+\.\d+/, shell_output("#{bin}/lilyterm --version"))
  end
end
