#!/bin/sh
# Usage: sh -x autogen.sh
#
# The distribution was made w/ these tools:
#  - autoconf (GNU Autoconf) 2.68
#  - automake (GNU automake) 1.11.5
#  - libtool (GNU libtool) 2.4.2
#  - guile-baux-tool (Guile-BAUX) 20120309.1509.1c4bb92

set -e

#############################################################################
# Guile-BAUX

guile-baux-tool import \
    re-prefixed-site-dirs \
    c2x \
    tsar \
    c-tsar \
    tsin \
    gen-scheme-wrapper \
    punify \
    gbaux-do

#############################################################################
# Autotools

autoreconf --verbose --force --install --symlink --warnings=all

# These override what ‘autoreconf --install’ creates.
# Another way is to use gnulib's config/srclist-update.
actually ()
{
    gnulib-tool --verbose --copy-file $1 $2
}
actually doc/INSTALL.UTF-8 INSTALL

# We aren't really interested in the backup files.
rm -f INSTALL~

######################################################################
# Done.

: Now run configure and make.
: You must pass the "--enable-maintainer-mode" option to configure.

# autogen.sh ends here
