require 'formula'

class Macgpg2 < Formula
  url 'ftp://ftp.gnupg.org/gcrypt/gnupg/gnupg-2.0.19.tar.bz2'
  homepage 'http://www.gnupg.org/'
  sha1 '190c09e6688f688fb0a5cf884d01e240d957ac1f'
  
  depends_on 'libiconv'
  depends_on 'gettext'
  depends_on 'pth'
  depends_on 'libusb-compat'
  depends_on 'libgpg-error'
  depends_on 'libassuan'
  depends_on 'libgcrypt'
  depends_on 'libksba'
  depends_on 'zlib'
  depends_on 'pinentry'
  
  keep_install_names true
  
  def patches
    { :p1 => [DATA],
      :p0 => ["#{HOMEBREW_PREFIX}/Library/Formula/Patches/gnupg2/IDEA.patch",
              "#{HOMEBREW_PREFIX}/Library/Formula/Patches/gnupg2/cacheid.patch",
              "#{HOMEBREW_PREFIX}/Library/Formula/Patches/gnupg2/keysize.patch",
              "#{HOMEBREW_PREFIX}/Library/Formula/Patches/gnupg2/launchd.patch",
              "#{HOMEBREW_PREFIX}/Library/Formula/Patches/gnupg2/MacGPG2VersionString.patch",
              "#{HOMEBREW_PREFIX}/Library/Formula/Patches/gnupg2/options.skel.patch"] }
  end

  def install
    (var+'run').mkpath
    ENV.build_32_bit
    
    # so we don't use Clang's internal stdint.h
    ENV['gl_cv_absolute_stdint_h'] = '/usr/include/stdint.h'
    # It's necessary to add the -rpath to the LDFLAGS, otherwise
    # programs can't link to libraries using @rpath.
    ENV.prepend 'LDFLAGS', '-headerpad_max_install_names'
    ENV.prepend 'LDFLAGS', "-Wl,-rpath,@loader_path/../lib -Wl,-rpath,#{HOMEBREW_PREFIX}/lib"
    # For some reason configure fails to include the link to libresolve
    # which is necessary for pka and cert options for the keyserver to work.
    ENV.prepend 'LDFLAGS', '-lresolv'
    system "./configure", "--prefix=#{prefix}",
                          "--disable-maintainer-mode",
                          "--disable-dependency-tracking",
                          "--disable-gpgtar",
                          "--enable-standard-socket",
                          "--with-pinentry-pgm=#{HOMEBREW_PREFIX}/libexec/pinentry-mac.app/Contents/MacOS/pinentry-mac",
                          "--with-gpg-error-prefix=#{HOMEBREW_PREFIX}",
                          "--with-libgcrypt-prefix=#{HOMEBREW_PREFIX}",
                          "--with-libassuan-prefix=#{HOMEBREW_PREFIX}",
                          "--with-ksba-prefix=#{HOMEBREW_PREFIX}",
                          "--with-pth-prefix=#{HOMEBREW_PREFIX}",
                          "--with-zlib=#{HOMEBREW_PREFIX}",
                          "--with-libiconv-prefix=#{HOMEBREW_PREFIX}",
                          "--with-libintl-prefix=#{HOMEBREW_PREFIX}"
    
    system "make"
    system "make check"
    system "make install"

    # conflicts with a manpage from the 1.x formula, and
    # gpg-zip isn't installed by this formula anyway
    #rm man1+'gpg-zip.1'
  end
end

__END__
# fix runtime data location
# http://git.gnupg.org/cgi-bin/gitweb.cgi?p=gnupg.git;a=commitdiff;h=c3f08dc
diff --git a/common/homedir.c b/common/homedir.c
index 5f2e31e..d797b68 100644
--- a/common/homedir.c
+++ b/common/homedir.c
@@ -365,7 +365,7 @@ dirmngr_socket_name (void)
     }
   return name;
 #else /*!HAVE_W32_SYSTEM*/
-  return "/var/run/dirmngr/socket";
+  return "HOMEBREW_PREFIX/var/run/dirmngr/socket";
 #endif /*!HAVE_W32_SYSTEM*/
 }
 
diff --git a/common/homedir.c b/common/homedir.c
index bdce3d1..4cc4ab9 100644
--- a/common/homedir.c
+++ b/common/homedir.c
@@ -338,6 +338,37 @@ gnupg_localedir (void)
     }
   return name;
 #else /*!HAVE_W32_SYSTEM*/
+  char path[3096];
+  uint32_t size = sizeof(path);
+  if (_NSGetExecutablePath(path, &size) != 0)
+      printf("buffer too small to get executable path; need size %u\n", size);
+  
+  char actualpath [PATH_MAX];
+  char *ptr;
+  ptr = realpath(path, actualpath);
+  // Find the last / in the path. 
+  char *c = strrchr(ptr, (int)'/');
+  // Set the post to the / in the path.
+  int pos = c - ptr;
+  // Only copy the without the executable name.
+  char *dirname_path = malloc((pos * sizeof(char)) + 1);
+  memcpy(dirname_path, ptr, pos);
+  dirname_path[pos+1] = '\0';
+  /* Check if ../share/locale exists. If so, use that path
+   * otherwise try LOCALEDIR.
+   */
+  char *locale_path = NULL;
+  asprintf(&locale_path, "%s/../share/locale", dirname_path);
+  // The path contains relative parts, so let's make them absolute.
+  char complete_path[PATH_MAX];
+  char *final_dir;
+  final_dir = realpath(locale_path, complete_path);
+  char *real_dir = complete_path == NULL ? final_dir : complete_path;
+  // Test if the locale dir exists.
+  struct stat s;
+  if(stat(real_dir, &s) == 0 && s.st_mode & S_IFDIR)
+      return real_dir;
+  // Not found, return the fixed localedir.
   return LOCALEDIR;
 #endif /*!HAVE_W32_SYSTEM*/
 }

diff --git a/common/homedir.c b/common/homedir.c
index 48f1e75..d7898d8 100644
--- a/common/homedir.c
+++ b/common/homedir.c
@@ -21,6 +21,11 @@
 #include <stdlib.h>
 #include <errno.h>
 #include <fcntl.h>
+#include <limits.h>
+#include <stdio.h>
+#include <stdint.h>
+#include <string.h>
+#include <sys/stat.h>
 
 #ifdef HAVE_W32_SYSTEM
 #include <shlobj.h>

diff --git a/common/i18n.c b/common/i18n.c
index db5ddf5..c34fcc7 100644
--- a/common/i18n.c
+++ b/common/i18n.c
@@ -37,7 +37,7 @@ i18n_init (void)
 #else
 # ifdef ENABLE_NLS
   setlocale (LC_ALL, "" );
-  bindtextdomain (PACKAGE_GT, LOCALEDIR);
+  bindtextdomain (PACKAGE_GT, gnupg_localedir ());
   textdomain (PACKAGE_GT);
 # endif
 #endif
