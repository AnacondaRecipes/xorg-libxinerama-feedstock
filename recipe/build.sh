#!/bin/bash

set -e

# Adopt a Unix-friendly path if we're on Windows (see bld.bat).
[ -n "$PATH_OVERRIDE" ] && export PATH="$PATH_OVERRIDE"

# On Windows we want $LIBRARY_PREFIX in both "mixed" (C:/Conda/...) and Unix
# (/c/Conda) forms, but Unix form is often "/" which can cause problems.
if [ -n "$LIBRARY_PREFIX_M" ] ; then
    mprefix="$LIBRARY_PREFIX_M"
    if [ "$LIBRARY_PREFIX_U" = / ] ; then
        uprefix=""
    else
        uprefix="$LIBRARY_PREFIX_U"
    fi
else
    mprefix="$PREFIX"
    uprefix="$PREFIX"
fi

if [ -n "$CYGWIN_PREFIX" ] ; then
    export ACLOCAL=aclocal-$am_version
    export AUTOMAKE=automake-$am_version
    autoreconf_args=(
        --force
        --install
        -I "$mprefix/share/aclocal"
        -I "$BUILD_PREFIX_M/Library/usr/share/aclocal"
    )
    autoreconf "${autoreconf_args[@]}"
    # ./configure needs this
    export CPP=x86_64-w64-mingw32-cpp.exe

    # And we need to add the search path that lets libtool find the
    # msys2 stub libraries for ws2_32.
    # Look in standard mingw-w64 library locations
    platlibs=$(cd $(dirname $($CC --print-prog-name=ld))/../sysroot/usr/lib && pwd -W)
    test -f $platlibs/libws2_32.a || { echo "error locating libws2_32" ; exit 1 ; }
    export LDFLAGS="$LDFLAGS -L$platlibs"

    # Explicitly set preprocessor to use gcc in preprocessing mode
    export CPP="gcc -E"

    # Add configure flags to help with Windows builds
    configure_args+=(
        --build=x86_64-w64-mingw32
        --host=x86_64-w64-mingw32
    )

    # Needed to get X11/X.h
    export CFLAGS="$CFLAGS -I$LIBRARY_PREFIX_U/include"
else
    # Get an updated config.sub and config.guess
    cp $BUILD_PREFIX/share/gnuconfig/config.* .
    
    export LC_ALL=C
    export LANG=C

    # for other platforms we just need to reconf to get the correct achitecture
    libtoolize --force
    aclocal -I $PREFIX/share/aclocal -I $BUILD_PREFIX/share/aclocal
    autoheader
    autoconf
    automake --force-missing --add-missing --include-deps
    export CONFIG_FLAGS="--build=${BUILD}"
fi

if [[ "$(uname)" == "Darwin" ]]; then
    export CPP=clang-cpp
    ln -s $BUILD_PREFIX/bin/clang-cpp $BUILD_PREFIX/bin/cpp
fi

autoreconf --force --verbose --install "${autoreconf_args[@]}"

export PKG_CONFIG_LIBDIR=$uprefix/lib/pkgconfig:$uprefix/share/pkgconfig
configure_args=(
    --prefix=$mprefix
    --disable-static
    --disable-dependency-tracking
    --disable-selective-werror
    --disable-silent-rules
)

# Unix domain sockets aren't gonna work on Windows
if [ -n "$CYGWIN_PREFIX" ] ; then
    configure_args+=(--disable-unix-transport)
fi

if [[ "${CONDA_BUILD_CROSS_COMPILATION}" == "1" ]]; then
    export xorg_cv_malloc0_returns_null=yes
    configure_args+=(
        --enable-malloc0returnsnull
    )
fi

./configure "${configure_args[@]}"
make -j$CPU_COUNT
make install

if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" != "1" || "${CROSSCOMPILING_EMULATOR}" != "" ]]; then
    make check
fi

rm -rf $uprefix/share/man
