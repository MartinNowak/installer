#!/bin/bash


set -e -o pipefail


# error function
ferror(){
	echo "==========================================================" >&2
	echo $1 >&2
	echo $2 >&2
	echo "==========================================================" >&2
	exit 1
}


# check if in debian like system
if test ! -f /etc/fedora-release ; then
	ferror "Refusing to build on a non-fedora like system" "Exiting..."
fi


# show help
if test -z $1 ;then
	echo "Script to create dmd v2 binary rpm packages."
	echo
	echo "Usage:"
	echo " " $0 "-v\"version\" -m\"model\" [-f]"
	echo
	echo "Options:"
	echo "  -v       dmd version (mandatory)"
	echo "  -m       32 or 64 (mandatory)"
	echo "  -f       force to rebuild"
	exit
fi

if test "$1" == "-n"; then
    DRY=echo
    shift
fi

# check if too many parameters
if test $# -gt 3 ;then
	ferror "Too many arguments" "Exiting..."
fi


# check version parameter
if test "${1:0:2}" != "-v" ;then
	ferror "Unknown first argument (-v)" "Exiting..."
else
	VER="${1:2}"
	if ! [[ $VER =~ ^[0-9]"."[0-9][0-9][0-9]$ || $VER =~ ^[0-9]"."[0-9][0-9][0-9]"."[0-9]$ ]]
	then
		ferror "incorrect version number" "Exiting..."
	elif test ${VER:0:1} -ne 2
	then
		ferror "for dmd v2 only" "Exiting..."
	elif test ${VER:0:1}${VER:2:3} -lt 2063
	then
		ferror "dmd v2.063 and newer only" "Exiting..."
	fi
fi
if test "${VER:5:2}" != ""; then
    RELEASE=${VER:6:1}
    VER=${VER:0:5}
fi

# check model parameter
if test $# -eq 1 ;then
	ferror "Second argument is mandatory (-m[32-64])" "Exiting..."
elif test "$2" != "-m32" -a "$2" != "-m64" ;then
	ferror "Unknown second argument '$2'" "Exiting..."
fi


# check forced build parameter
if test $# -eq 3 -a "$3" != "-f" ;then
	ferror "Unknown third argument '$3'" "Exiting..."
fi


# needed commands function
E=0
fcheck(){
	if ! `which $1 1>/dev/null 2>&1` ;then
		LIST=$LIST" "$1
		E=1
	fi
}
fcheck rpmdev-setuptree
fcheck rpmbuild
fcheck make
fcheck cc
fcheck g++
if [ $E -eq 1 ]; then
    ferror "Missing commands on Your system:" "$LIST"
fi

MAINTAINER="Martin Nowak <code@dawg.eu>"
# example (2.064.2): VER=2.064, RELEASE=2
# dlang uses 2.064 for the first release (instead of 2.064.0) :(
if [ "$RELEASE" == "" ]
then
    DVER=${VER}
    RELEASE=0
else
    DVER=${VER}.${RELEASE}
fi
DESTDIR=`pwd`
if test "$2" = "-m64" ;then
    ARCH="x86_64"
    FARCH="x86-64"
    MODEL="64"
elif test "$2" = "-m32" ;then
    ARCH="i386"
    FARCH="x86-32"
    MODEL="32"
fi

# create rpmbuild tree
${DRY} rpmdev-setuptree

# create spec file
SPECFILE=${HOME}/rpmbuild/SPECS/dmd.spec

PROJECTS="dmd druntime phobos tools"

cat > ${SPECFILE} <<EOF
Name: dmd
Version: ${VER}
Release: ${RELEASE}
Summary: Digital Mars D Compiler

Group: Development/Languages
License: see /usr/share/doc/dmd
URL: http://dlang.org/
Source0: https://github.com/D-Programming-Language/dmd/archive/v${DVER}/dmd-${VER}.${RELEASE}.tar.gz
Source1: https://github.com/D-Programming-Language/druntime/archive/v${DVER}/druntime-${VER}.${RELEASE}.tar.gz
Source2: https://github.com/D-Programming-Language/phobos/archive/v${DVER}/phobos-${VER}.${RELEASE}.tar.gz
Source3: https://github.com/D-Programming-Language/tools/archive/v${DVER}/tools-${VER}.${RELEASE}.tar.gz
Source4: https://github.com/D-Programming-Language/installer/archive/v${DVER}/installer-${VER}.${RELEASE}.tar.gz
Packager: Martin Nowak <code@dawg.eu>

ExclusiveArch: ${ARCH}
Requires: glibc-devel(${FARCH}), gcc, libcurl(${FARCH}), xdg-utils
BuildRequires: libcurl-devel(${FARCH})
Provides: dmd = ${VER}.${RELEASE}, dmd(${FARCH}) = ${VER}.${RELEASE}

%description
D is a systems programming language. Its focus is on combining the power and
high performance of C and C++ with the programmer productivity of modern
languages like Ruby and Python. Special attention is given to the needs of
quality assurance, documentation, management, portability and reliability.

The D language is statically typed and compiles directly to machine code.
It\047s multiparadigm, supporting many programming styles: imperative,
object oriented, functional, and metaprogramming. It\047s a member of the C
syntax family, and its appearance is very similar to that of C++.

It is not governed by a corporate agenda or any overarching theory of
programming. The needs and contributions of the D programming community form
the direction it goes.

Main designer: Walter Bright

%prep

# unpack dmd druntime phobos tools
%setup -q -c
%setup -q -T -D -a 1
%setup -q -T -D -a 2
%setup -q -T -D -a 3
%setup -q -T -D -a 4

# unversioned symlinks
for proj in dmd druntime phobos tools installer; do
     ln -s \${proj}-${DVER} \${proj}
done


%build

# provide a working dmd.conf for the local dmd compiler
echo "
[Environment${MODEL}]
DFLAGS=-I%@P%/../../druntime/import -I%@P%/../../phobos -L-L%@P%/../../phobos/generated/linux/release/${MODEL} -L--export-dynamic
" > dmd/src/dmd.conf

# 2.064.2 came with an outdated VERSION file
echo ${DVER} > dmd/VERSION

for proj in dmd druntime phobos; do
    pushd \${proj}
    make -f posix.mak MODEL=${MODEL} RELEASE=1 DMD=../dmd/src/dmd -j4
    popd
done
pushd tools
make -f posix.mak MODEL=${MODEL} RELEASE=1 DMD=../dmd/src/dmd rdmd ddemangle
popd

%install

for proj in dmd druntime phobos; do
    pushd \${proj}
    make -f posix.mak install MODEL=${MODEL} RELEASE=1 DMD=../dmd/src/dmd -j4
    popd
done
# tools build is broken, so we can't use the install target
# pushd tools
# make -f posix.mak install MODEL=${MODEL} RELEASE=1 DMD=../dmd/src/dmd PREFIX=../install rdmd ddemangle
# popd
cp tools/generated/linux/${MODEL}/{rdmd,ddemangle} install/bin

mkdir -p %{buildroot}{%{_bindir},%{_libdir},%{_includedir}/dmd,%{_datadir}/dmd,%{_datadir}/doc/dmd,}
install -Dm755 install/bin/{dmd,ddemangle,rdmd} %{buildroot}%{_bindir}
cp -r install/import/* %{buildroot}%{_includedir}/dmd
cp -r install/man %{buildroot}%{_datadir}
cp -r install/samples %{buildroot}%{_datadir}/dmd
install -Dm644 install/{dmd-artistic.txt,dmd-backendlicense.txt,druntime-LICENSE.txt,phobos-LICENSE.txt} %{buildroot}%{_datadir}/doc/dmd

LIBPHOBOS=phobos/generated/linux/release/${MODEL}/libphobos2
install -Dm755 \${LIBPHOBOS}.a %{buildroot}%{_libdir}
## @@ BUG @@ ## phobos/posix.mak doesn't use point releases
# install -Dm755 \${LIBPHOBOS}.so.${VER:2:1}.${VER:3:2}.${RELEASE} %{buildroot}%{_libdir} # libphobos2.so.0.64.2
install -Dm755 \${LIBPHOBOS}.so.${VER:2:1}.${VER:3:2}.0 %{buildroot}%{_libdir} # libphobos2.so.0.64.0
# copy symlinks
cp -P \${LIBPHOBOS}.so %{buildroot}%{_libdir}
cp -P \${LIBPHOBOS}.so.${VER:2:1}.${VER:3:2} %{buildroot}%{_libdir} # libphobos2.so.0.64

mkdir -p %{buildroot}%{_sysconfdir}/bash_completion.d
install -Dm755 installer/linux/dmd-completion %{buildroot}%{_sysconfdir}/bash_completion.d/dmd

echo "
[Environment${MODEL}]
DFLAGS=-I%{_includedir}/dmd -L-L%{_libdir} -L--export-dynamic
" > %{buildroot}%{_sysconfdir}/dmd.conf

%clean

for proj in dmd druntime phobos tools; do
    make -C \${proj} -f posix.mak clean
done
rm -rf install

%post

/sbin/ldconfig

%postun

/sbin/ldconfig

%files

%{_bindir}/ddemangle
%{_bindir}/dmd
%{_bindir}/rdmd
%{_libdir}/libphobos2.a
%{_libdir}/libphobos2.so*
%{_datadir}/dmd/*
%{_datadir}/doc/dmd/*
%{_datadir}/man/*
%{_includedir}/dmd/*
%{_sysconfdir}/bash_completion.d/dmd
%{_sysconfdir}/dmd.conf
EOF

${DRY} spectool -R -g ${SPECFILE}
${DRY} rpmbuild --target=${ARCH} -ba ${SPECFILE}
