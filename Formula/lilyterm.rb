class Lilyterm < Formula
  desc "Light and easy to use libvte based terminal emulator"
  homepage "https://github.com/ebal/LilyTerm"
  license "GPL-3.0-or-later"
  head "https://github.com/ebal/LilyTerm.git", branch: "main"

  stable do
    url "https://github.com/ebal/LilyTerm/archive/refs/tags/v0.9.10.tar.gz"
    sha256 "4ef9759b23641681cef74d38ca2e4cd6a94aef640819849e6a3218498863273e"

    # Build and run safely on macOS: a socket path that fits the 104 byte
    # sun_path, the peer uid check with getpeereid(), and Apple's strip.
    # Drop this once a release has it.
    patch :DATA
  end

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

      macOS has no /proc, so tab names do not follow the running command
      or the current directory, and there is no warning about running
      programs when a tab is closed.

      The system wide settings are in:
        #{etc}/xdg/lilyterm.conf
    EOS
  end

  test do
    assert_match(/^LilyTerm \d+\.\d+/, shell_output("#{bin}/lilyterm --version"))
  end
end

__END__
diff --git a/src/Makefile b/src/Makefile
index 154bbd4..13332a1 100644
--- a/src/Makefile
+++ b/src/Makefile
@@ -82,8 +82,12 @@ endif
 all: default
 ifeq ($(DEBUG), N)
 	@ $(PRINTF) "\033[1;36m** striping \033[1;32m$(BINARY)\033[1;36m ...\033[0m\n"
+ifeq ($(shell uname), Darwin)
+	$(VERBOSITY_OUTPUT) $(STRIP) -x $(BINARY)
+else
 	$(VERBOSITY_OUTPUT) $(STRIP) --remove-section=.comment --remove-section=.note $(BINARY)
 endif
+endif
 
 .PHONY: default
 ifneq ($(SAFEMODE), N)
diff --git a/src/main.h b/src/main.h
index 3b7d1b1..d780904 100644
--- a/src/main.h
+++ b/src/main.h
@@ -31,8 +31,6 @@
 
 #include "lilyterm.h"
 
-// the max size of saddr.sun_path in Linux is 108!
-#define UNIX_PATH_MAX 108
 
 gboolean set_fd_non_block(gint *fd);
 gboolean init_socket_server(GSourceFunc read_function);
diff --git a/src/socket.c b/src/socket.c
index 2094d75..96e1097 100644
--- a/src/socket.c
+++ b/src/socket.c
@@ -86,8 +86,6 @@
 
 #include "socket.h"
 
-// the max size of saddr.sun_path in Linux is 108!
-#define UNIX_PATH_MAX 108
 # define MAX_BACKLOG 100
 
 typedef enum {
@@ -203,13 +201,14 @@ gboolean init_socket_data(gchar *package_name)
 		tmp_dir = g_get_tmp_dir();
 
 	if (tmp_dir)
-		g_snprintf(address.sun_path, UNIX_PATH_MAX, "%s/.%s_%s%s",
+		g_snprintf(address.sun_path, sizeof(address.sun_path), "%s/.%s_%s%s",
 			   tmp_dir ,package_name, g_get_user_name(),
 			   gdk_display_get_name(gdk_display_get_default()));
 	else
 		return socket_fault(GTK_SOCKET_ERROR_TMP_DIR, error, NULL, FALSE);
 
-	address.sun_path[UNIX_PATH_MAX-1] = address.sun_path[UNIX_PATH_MAX-2] = '\0';
+	// sun_path is 108 bytes on Linux, but only 104 on macOS and the BSDs
+	address.sun_path[sizeof(address.sun_path)-1] = address.sun_path[sizeof(address.sun_path)-2] = '\0';
 	address_len = sizeof(address);
 
 	if (! init_socket_fd()) return FALSE;
@@ -380,13 +379,19 @@ gboolean accept_socket(GIOChannel *source, GIOCondition condition, GSourceFunc r
 
 		if (read_fd < 0) return socket_fault(GTK_SOCKET_ERROR_CREATE_SOCKET_FILE, error, source, FALSE);
 
-#ifdef SO_PEERCRED
 		// The request ends up as a command line that is executed with our
 		// privileges: never take one from another user.
+#ifdef SO_PEERCRED
 		struct ucred peer;
 		socklen_t peer_len = sizeof(peer);
 		if ((getsockopt(read_fd, SOL_SOCKET, SO_PEERCRED, &peer, &peer_len) < 0) ||
 		    (peer_len != sizeof(peer)) || (peer.uid != getuid()))
+#else
+		// macOS and the BSDs
+		uid_t peer_uid;
+		gid_t peer_gid;
+		if ((getpeereid(read_fd, &peer_uid, &peer_gid) < 0) || (peer_uid != getuid()))
+#endif
 		{
 			g_warning("Refused a request on the %s socket: it does not come from uid %d.",
 				  PACKAGE, (gint) getuid());
@@ -394,7 +399,6 @@ gboolean accept_socket(GIOChannel *source, GIOCondition condition, GSourceFunc r
 			// keep the socket server alive
 			return TRUE;
 		}
-#endif
 
 		if ( ! set_fd_non_block(&read_fd)) return FALSE;
 
