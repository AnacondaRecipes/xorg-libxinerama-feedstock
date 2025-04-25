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
    autoreconf_args=(
        -I "$mprefix/share/aclocal"
        -I "$BUILD_PREFIX_M/Library/usr/share/aclocal"
    )

    # And we need to add the search path that lets libtool find the
    # msys2 stub libraries for ws2_32.
    # Look in standard mingw-w64 library locations
    for lib_path in "$BUILD_PREFIX_M/Library/mingw-w64/bin" "$BUILD_PREFIX_M/Library/bin" "$mprefix/Library/mingw-w64/lib" "$mprefix/Library/lib"; do
        if [ -d "$lib_path" ]; then
            # Convert to Windows path
            win_path=$(cygpath -w "$lib_path")
            echo "Adding path to library search: $win_path"
            export PATH="$PATH:$win_path"
            export LIBRARY_PATH="$LIBRARY_PATH:$win_path"
            # For ld
            export LDFLAGS="$LDFLAGS -L$win_path"
        fi
    done
else
    # Get an updated config.sub and config.guess
    cp $BUILD_PREFIX/share/gnuconfig/config.* .

    autoreconf_args=(
        -I "${PREFIX}/share/aclocal"
        -I "${BUILD_PREFIX}/share/aclocal"
    )
fi

am_version=1.15 # keep sync'ed with am_version in meta.yaml
export ACLOCAL=aclocal-$am_version
export AUTOMAKE=automake-$am_version

autoreconf --force --verbose --install "${autoreconf_args[@]}"

export PKG_CONFIG_LIBDIR=$uprefix/lib/pkgconfig:$uprefix/share/pkgconfig
configure_args=(
    --prefix=$mprefix
    --disable-static
    --disable-dependency-tracking
    --disable-selective-werror
    --disable-silent-rules
)

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
