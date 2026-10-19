class Lilyterm < Formula
  desc "Light and easy to use libvte based terminal emulator"
  homepage "https://github.com/ebal/LilyTerm"
  license "GPL-3.0-or-later"
  revision 4
  head "https://github.com/ebal/LilyTerm.git", branch: "main"

  stable do
    url "https://github.com/ebal/LilyTerm/archive/refs/tags/v0.9.10.tar.gz"
    sha256 "4ef9759b23641681cef74d38ca2e4cd6a94aef640819849e6a3218498863273e"

    # Build and run safely on macOS: a socket path that fits the 104 byte
    # sun_path, the peer uid check with getpeereid(), Apple's strip, theme
    # colors with a valid alpha (VTE refused the foreground color), the
    # LilyTerm icon in the Dock, menus with an opaque background, and a
    # visible title bar (no RGBA window unless use_rgba = 1), the window
    # in front at start, and [Quit] in the Dock.
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

__END__
diff --git a/src/Makefile b/src/Makefile
index 154bbd4..51a8129 100644
--- a/src/Makefile
+++ b/src/Makefile
@@ -72,6 +72,10 @@ INCLUDES = -DBINARY=\"$(BINARY)\" \
 ifeq ($(BSD), 1)
 	INCLUDES += -DBSD
 endif
+ifeq ($(shell uname), Darwin)
+	# objc_msgSend() for the Dock icon, see init_macos()
+	LIBS += -lobjc
+endif
 ifeq ($(VERBOSITY), Y)
 	VERBOSITY_OUTPUT =
 else
@@ -82,8 +86,12 @@ endif
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
diff --git a/src/lilyterm.h b/src/lilyterm.h
index b53cfb4..d76d5dd 100644
--- a/src/lilyterm.h
+++ b/src/lilyterm.h
@@ -123,6 +123,7 @@ gboolean idle_set_vte_font_to_selected(struct Window *win_data);
 void dim_window(struct Window *win_data, gint dim_window);
 void clear_window(struct Window *win_data);
 void set_window_icon(GtkWidget *window);
+void init_macos(void);
 gboolean window_quit(GtkWidget *window, GdkEvent *event, struct Window *win_data);
 GString *close_multi_tabs(struct Window *win_data, int window_no);
 gboolean display_child_process_dialog (GString *child_process_list, struct Window *win_data, gsize style);
diff --git a/src/main.c b/src/main.c
index b81a27c..c5990f5 100644
--- a/src/main.c
+++ b/src/main.c
@@ -137,6 +137,9 @@ int main( int   argc,
 	// Convert the GdkColor to GdkRGBA
 	convert_system_color_to_rgba();
 
+	// the Dock icon, the menu background, the front window and [Quit] in the Dock on macOS
+	init_macos();
+
 	//GtkNotebook *new_window(int argc,
 	//			char *argv[],
 	//			gchar *shell,
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
diff --git a/src/misc.c b/src/misc.c
index 6046cbe..6066da7 100644
--- a/src/misc.c
+++ b/src/misc.c
@@ -689,6 +689,8 @@ GdkRGBA convert_color_to_rgba(GdkColor color)
 	rgba.red = (gdouble)(color.red>>8)/0xFF;
 	rgba.green = (gdouble)(color.green>>8)/0xFF;
 	rgba.blue = (gdouble)(color.blue>>8)/0xFF;
+	// VTE refuses a color with an alpha out of [0, 1]: never leave it uninitialized
+	rgba.alpha = 1.0;
 
 	return rgba;
 }
diff --git a/src/profile.c b/src/profile.c
index 186b330..d408f4e 100644
--- a/src/profile.c
+++ b/src/profile.c
@@ -2712,10 +2712,14 @@ void init_rgba(struct Window *win_data)
 
 	if (win_data->use_rgba==2)
 	{
-		if (screen)
-			win_data->use_rgba = gdk_screen_is_composited(screen);
-		else
-			goto FINISH;
+		if (screen==NULL) goto FINISH;
+#ifdef __APPLE__
+		// GTK+ 3 on macOS draws an RGBA window clear, its title bar included,
+		// so there is nothing to see or to drag. Only on request (use_rgba = 1).
+		win_data->use_rgba = 0;
+#else
+		win_data->use_rgba = gdk_screen_is_composited(screen);
+#endif
 	}
 
 	if (win_data->use_rgba)
diff --git a/src/property.c b/src/property.c
index 9748da9..d747ed1 100644
--- a/src/property.c
+++ b/src/property.c
@@ -73,6 +73,11 @@ void adjust_ansi_color(GdkRGBA *color, GdkRGBA *color_orig, gdouble color_bright
 		color->green = (1 + color_brightness) * color_orig->green;
 		color->blue = (1 + color_brightness) * color_orig->blue;
 	}
+	// VTE refuses a color with any component out of [0, 1]
+	color->red = CLAMP(color->red, 0, 1);
+	color->green = CLAMP(color->green, 0, 1);
+	color->blue = CLAMP(color->blue, 0, 1);
+	color->alpha = 1.0;
 }
 
 void generate_all_color_datas(struct Window *win_data)
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
 
diff --git a/src/window.c b/src/window.c
index 53ba322..c5099a7 100644
--- a/src/window.c
+++ b/src/window.c
@@ -18,6 +18,10 @@
  */
 
 #include "window.h"
+#ifdef __APPLE__
+#  include <objc/runtime.h>
+#  include <objc/message.h>
+#endif
 
 extern gboolean proc_exist;
 
@@ -451,6 +455,98 @@ void set_window_icon(GtkWidget *window)
 		gtk_window_set_icon_name(GTK_WINDOW(window), BINARY);
 }
 
+#ifdef __APPLE__
+// The four char codes of the Apple event the Dock sends for [Quit]
+#  define MACOS_EVENT_CLASS_CORE 0x61657674	// 'aevt'
+#  define MACOS_EVENT_ID_QUIT 0x71756974	// 'quit'
+
+// the same as [Quit] on the right click menu: it asks first if programs run in the tabs
+static gboolean macos_quit(gpointer data)
+{
+	struct Window *win_data = NULL;
+	if (active_window) win_data = (struct Window *)g_object_get_data(G_OBJECT(active_window), "Win_Data");
+	if ((win_data==NULL) && window_list) win_data = window_list->data;
+	if (win_data)
+		main_quit(NULL, win_data);
+	else
+		quit_gtk();
+	return FALSE;
+}
+
+// The handler of the quit Apple event. A dialog may show up: run it from the main loop.
+static void macos_quit_event(id self, SEL cmd, id event, id reply)
+{
+	g_idle_add(macos_quit, NULL);
+}
+
+// GTK+ 3 only activates the application on a click, so the first window
+// would open behind the terminal LilyTerm was started from.
+static gboolean macos_activate(gpointer data)
+{
+	id app = ((id (*)(Class, SEL))objc_msgSend)(objc_getClass("NSApplication"), sel_registerName("sharedApplication"));
+	((void (*)(id, SEL, BOOL))objc_msgSend)(app, sel_registerName("activateIgnoringOtherApps:"), (BOOL)1);
+	return FALSE;
+}
+#endif
+
+// GTK+ 3 on macOS ignores the window icon for the Dock, draws the menus
+// without a background, does not bring the application to the front and
+// ignores [Quit] in the Dock (only GtkApplication handles it). Fix them
+// through AppKit and CSS.
+void init_macos(void)
+{
+#ifdef __APPLE__
+#ifdef DETAIL
+	g_debug("! Launch init_macos()");
+#endif
+	g_idle_add(macos_activate, NULL);
+
+	Class handler_class = objc_allocateClassPair(objc_getClass("NSObject"), "LilyTermQuitHandler", 0);
+	Class manager_class = objc_getClass("NSAppleEventManager");
+	if (handler_class && manager_class)
+	{
+		SEL handle_quit = sel_registerName("handleQuit:withReplyEvent:");
+		class_addMethod(handler_class, handle_quit, (IMP)macos_quit_event, "v@:@@");
+		objc_registerClassPair(handler_class);
+		id handler = ((id (*)(Class, SEL))objc_msgSend)(handler_class, sel_registerName("new"));
+		id manager = ((id (*)(Class, SEL))objc_msgSend)(manager_class, sel_registerName("sharedAppleEventManager"));
+		((void (*)(id, SEL, id, SEL, uint32_t, uint32_t))objc_msgSend)
+			(manager, sel_registerName("setEventHandler:andSelector:forEventClass:andEventID:"),
+			 handler, handle_quit, MACOS_EVENT_CLASS_CORE, MACOS_EVENT_ID_QUIT);
+	}
+
+	Class app_class = objc_getClass("NSApplication");
+	Class image_class = objc_getClass("NSImage");
+	Class string_class = objc_getClass("NSString");
+	if (app_class && image_class && string_class && g_file_test(ICON_PATH, G_FILE_TEST_IS_REGULAR))
+	{
+		id path = ((id (*)(Class, SEL, const char *))objc_msgSend)
+				(string_class, sel_registerName("stringWithUTF8String:"), ICON_PATH);
+		id image = ((id (*)(Class, SEL))objc_msgSend)(image_class, sel_registerName("alloc"));
+		image = ((id (*)(id, SEL, id))objc_msgSend)(image, sel_registerName("initWithContentsOfFile:"), path);
+		if (image)
+		{
+			id app = ((id (*)(Class, SEL))objc_msgSend)(app_class, sel_registerName("sharedApplication"));
+			((void (*)(id, SEL, id))objc_msgSend)(app, sel_registerName("setApplicationIconImage:"), image);
+			((void (*)(id, SEL))objc_msgSend)(image, sel_registerName("release"));
+		}
+	}
+
+	GdkScreen *screen = gdk_screen_get_default();
+	if (screen)
+	{
+		GtkCssProvider *css = gtk_css_provider_new();
+		if (gtk_css_provider_load_from_data(css,
+						    "menu, .menu, .context-menu { background-color: @theme_bg_color; }\n"
+						    "window.popup { background-color: @theme_bg_color; }\n",
+						    -1, NULL))
+			gtk_style_context_add_provider_for_screen(screen, GTK_STYLE_PROVIDER(css),
+								  GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
+		g_object_unref(css);
+	}
+#endif
+}
+
 gboolean window_quit(GtkWidget *window, GdkEvent *event, struct Window *win_data)
 {
 #ifdef DETAIL
