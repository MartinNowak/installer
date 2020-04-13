/++
Prerequisites:
-------------------------
A working dmd installation to compile this script (also requires libcurl).
Install Vagrant (https://learnchef.opscode.com/screencasts/install-vagrant/)
Install VirtualBox (https://learnchef.opscode.com/screencasts/install-virtual-box/)
+/
import std.algorithm, std.conv, std.exception, std.file, std.path, std.process, std.stdio, std.string, std.range;
import common;

version (NoVagrant) {} else
version (Posix) {} else { static assert(0, "This must be run on a Posix machine."); }
static assert(__VERSION__ >= 2067, "Requires dmd >= 2.067 with a fix for Bugzilla 8269.");

/// Open Source OS boxes are from http://www.vagrantbox.es/
/// For each box additional setup steps were performed, afterwards the boxes were repackaged.

/// Name: create_dmd_release-freebsd-32
/// https://vagrantcloud.com/bento/freebsd-11.2-i386
/// URL: https://app.vagrantup.com/bento/boxes/freebsd-11.2-i386/versions/201807.12.0/providers/virtualbox.box
/// Setup: sudo pkg install bash curl git gmake rsync
enum freebsd_32 = Platform(OS.freebsd, Model._32);

/// Name: create_dmd_release-freebsd-64
/// https://vagrantcloud.com/bento/freebsd-11.2
/// URL: https://vagrantcloud.com/bento/boxes/freebsd-11.2/versions/201812.27.0/providers/virtualbox.box
/// Setup: sudo pkg install bash curl git gmake rsync
enum freebsd_64 = Platform(OS.freebsd, Model._64);

/// Name: create_dmd_release-linux
/// https://app.vagrantup.com/debian/boxes/stretch64
/// URL: https://vagrantcloud.com/debian/boxes/stretch64/versions/9.12.0/providers/virtualbox.box
/// Setup: sudo dpkg --add-architecture i386; sudo apt-get -y update; sudo apt-get -y install git g++-multilib dpkg-dev rpm rsync unzip libcurl3 libcurl3:i386 --no-install-recommends; sudo apt-get clean
enum linux_both = Platform(OS.linux, Model._both);

/// OSes that require licenses must be setup manually

/// Name: create_dmd_release-osx
/// Setup: Preparing OSX-10.8 box, https://gist.github.com/MartinNowak/8156507
enum osx_both = Platform(OS.osx, Model._both);

/// Name: create_dmd_release-windows
/// Setup: Preparing Win7x64 box, https://gist.github.com/MartinNowak/8270666
enum windows_both = Platform(OS.windows, Model._both);

version(Windows)
    enum platforms = [windows_both];
else
    enum platforms = [linux_both, windows_both, osx_both, freebsd_32, freebsd_64];

/// the LDC version to use to build dmd (on Windows), leave empty to use dmd
enum ldcVer = "1.20.0";

enum OS { freebsd, linux, osx, windows, }
enum Model { _both = 0, _32 = 32, _64 = 64 }
struct Platform
{
    @property string osS() { return to!string(os); }
    @property string modelS() { return model == Model._both ? "" : to!string(cast(uint)model); }
    string toString() { return model == Model._both ? osS : osS ~ "-" ~ modelS; }
    OS os;
    Model model;
}

struct Shell
{
    @disable this(this);

    this(string[] args)
    {
        _pipes = pipeProcess(args, Redirect.stdin);
    }

    void cmd(string s)
    {
        writeln("\033[33m", s, "\033[0m");
        _pipes.stdin.writeln(s);
    }

    ~this()
    {
        _pipes.stdin.close();
        // TODO: capture stderr and attach it to enforce
        enforce(wait(_pipes.pid) == 0);
        version(NoVagrant)
            if (_cwd) chdir(_cwd);
    }

    ProcessPipes _pipes;
    version(NoVagrant)
        string _cwd;
}

struct Box
{
    @disable this(this);

    this(Platform platform)
    {
        _platform = platform;

        _tmpdir = mkdtemp();

        version(NoVagrant) {} else {
            std.file.write(buildPath(_tmpdir, "Vagrantfile"), vagrantFile);

            // bring up the virtual box
            if (platform.os != OS.osx)
                run("cd "~_tmpdir~"; vagrant up");
            else
            {
                // retry to workaround infrequent OSX boot failure
                auto i = 0;
                for (; i < 3 && runStatus("cd "~_tmpdir~"; vagrant up"); ++i)
                    run("cd "~_tmpdir~"; vagrant destroy -f");
                enforce(i < 3, "Repeatedly failed to boot OSX box.");
            }
            _isUp = true;

            // save the ssh config file
            run("cd "~_tmpdir~"; vagrant ssh-config > ssh.cfg;");
        }
    }

    Shell shell()
    {
        string[] args = os == OS.windows ? ["powershell", "-Command", "-"] : ["bash", "-e"];
        version(NoVagrant)
        {
            auto cwd = getcwd();
            chdir(_tmpdir);
            auto sh = Shell(args);
            sh._cwd = cwd;
            return sh;
        }
        else
            return Shell(["ssh", "-F", sshcfg, "default"] ~ args);
    }

    void scp(string src, string tgt)
    {
        version(NoVagrant)
        {
            if (src.startsWith("default:"))
                src = _tmpdir ~ "/" ~ src[8..$];
            if (tgt.startsWith("default:"))
                tgt = _tmpdir ~ "/" ~ tgt[8..$];

            string[] srcs = split(src, " ");
            foreach(s; srcs)
                if (std.file.isFile(s))
                    copyFile(s, buildPath(tgt, baseName(s)));
                else
                    copyDirectory(s, tgt);
        }
        else
        {
            // run scp with retry as fetching sth. fails (Windows OpenSSH-server)
            auto cmd = "scp -r -F "~sshcfg~" "~src~" "~tgt~" > /dev/null";
            if (runStatus(cmd) && runStatus(cmd))
                run(cmd);
        }
    }

private:
    @property string vagrantFile()
    {
        auto res =
            `
            VAGRANTFILE_API_VERSION = "2"

            Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
                config.vm.box = "create_dmd_release-`~platform~`"
                # disable shared folders, because the guest additions are missing
                config.vm.synced_folder ".", "/vagrant", :disabled => true
                # use insecure ssh keys
                config.ssh.insert_key = false

                config.vm.provider :virtualbox do |vb|
                  vb.customize ["modifyvm", :id, "--memory", "4096"]
                  vb.customize ["modifyvm", :id, "--cpus", "4"]
                  vb.customize ["modifyvm", :id, "--accelerate3d", "off"]
                  vb.customize ["modifyvm", :id, "--audio", "none"]
                  vb.customize ["modifyvm", :id, "--usb", "off"]
                end
            `;
        if (os == OS.windows)
            res ~=
            `
                config.ssh.shell = 'powershell -Command -'
                config.vm.guest = :windows
            `;
        res ~=
            `
            end
            `;
        return res.outdent();
    }

    auto build(string ver, bool isBranch, bool skipDocs)
    {
        return runBuild(this, ver, isBranch, skipDocs);
    }

    ~this()
    {
        destroy();
    }

    void destroy()
    {
        try
        {
            if (_isUp) run("cd "~_tmpdir~"; vagrant destroy -f");
            rmdirDirectoryNoFail(_tmpdir);
        }
        finally
        {
            _isUp = false;
            _tmpdir = null;
        }
    }

    void halt()
    {
        try
            if (_isUp) run("cd "~_tmpdir~"; vagrant halt");
        finally
            _isUp = false;
    }

    @property string platform() { return _platform.toString; }
    @property string sshcfg() { return buildPath(_tmpdir, "ssh.cfg"); }

    Platform _platform;
    alias _platform this;
    string _tmpdir;
    bool _isUp;
}

string runCapture(string cmd)
{
    writeln("\033[36m", cmd, "\033[0m");
    auto result = executeShell(cmd);
    enforce(result.status == 0);
    return result.output.strip;
}

int runStatus(string cmd)
{
    writeln("\033[36m", cmd, "\033[0m");
    return wait(spawnShell(cmd));
}

void run(string cmd)
{
    enforce(runStatus(cmd) == 0);
}

//------------------------------------------------------------------------------

auto addPrefix(R)(R rng, string prefix)
{
    import std.algorithm : map;
    return rng.map!(a => prefix ~ a)();
}

//------------------------------------------------------------------------------
// Copy additional release binaries from the previous release

void prepareExtraBins(string workDir)
{
    auto extraBins = [
        windows_both : [
            "lib.exe", "optlink.exe", "make.exe", "replace.exe", "shell.exe"
        ].addPrefix("bin/").array,
        linux_both : ["bin32/dumpobj", "bin64/dumpobj", "bin32/obj2asm", "bin64/obj2asm"],
        freebsd_32 : ["bin32/dumpobj", "bin32/obj2asm", "bin32/shell"],
        freebsd_64 : [],
        osx_both : ["bin/dumpobj", "bin/obj2asm", "bin/shell"],
    ];

    foreach (platform; platforms)
        copyFiles(extraBins[platform].addPrefix("dmd2/"~platform.osS~"/").array(),
                  workDir~"/"~platform.toString~"/old-dmd", workDir~"/"~platform.osS~"/extraBins");
}

//------------------------------------------------------------------------------
// builds a dmd.VERSION.OS.MODEL.zip on the vanilla VirtualBox image

void runBuild(ref Box box, string ver, bool isBranch, bool skipDocs)
{
    with (box.shell())
    {
        string dmd, rdmd;
        final switch (box.os)
        {
        case OS.freebsd:
            dmd = "old-dmd/dmd2/freebsd/bin"~box.modelS~"/dmd";
            rdmd = "old-dmd/dmd2/freebsd/bin"~box.modelS~"/rdmd"~" --compiler="~dmd;
            break;
        case OS.linux:
            dmd = "old-dmd/dmd2/linux/bin64/dmd";
            rdmd = "old-dmd/dmd2/linux/bin64/rdmd --compiler="~dmd;
            break;
        case OS.windows:
            // copy libcurl needed for create_dmd_release and dlang.org
            cmd(`copy old-dmd\dmd2\windows\bin\libcurl.dll .`);
            cmd(`copy old-dmd\dmd2\windows\bin\libcurl.dll clones\dlang.org`);
            cmd(`copy old-dmd\dmd2\windows\lib\curl.lib clones\dlang.org`);

            if (ldcVer.empty)
                dmd = `old-dmd\dmd2\windows\bin\dmd.exe`;
            else
                dmd = `ldc\ldc2-`~ldcVer~`-windows-multilib\bin\ldmd2.exe`;
            rdmd = `old-dmd\dmd2\windows\bin\rdmd.exe`;
            break;
        case OS.osx:
            dmd = "old-dmd/dmd2/osx/bin/dmd";
            rdmd = "old-dmd/dmd2/osx/bin/rdmd --compiler="~dmd;
            break;
        }

        auto build = rdmd~" -g create_dmd_release --extras=extraBins --use-clone=clones --host-dmd="~dmd;
        if (box.model != Model._both)
            build ~= " --only-" ~ box.modelS;
        if (skipDocs)
            build ~= " --skip-docs";
        if (!isBranch)
            build ~= " --codesign";
        build ~= " " ~ ver;

        cmd(build);
    }

    // copy out created zip files
    box.scp("default:dmd."~ver~"."~box.platform~".zip", "build/");

    // Build package installers (TODO: move to create_dmd_release.d)
    if (!isBranch && !skipDocs) final switch (box.os)
    {
    case OS.freebsd:
        break;

    case OS.linux:
        with (box.shell())
        {
            cmd(`cp dmd.`~ver~`.linux.zip clones/installer/linux`);
            cmd(`cd clones/installer/linux`);
            cmd(`./build_all.sh -v`~ver);
            cmd(`ls *.deb`);
        }
        box.scp("'default:clones/installer/linux/*.{rpm,deb}'", "build/");
        break;

    case OS.windows:
        with (box.shell())
        {
            cmd(`cd clones\installer\windows`);
            cmd(`&'C:\Program Files (x86)\NSIS\makensis'`~
                ` '/DEmbedD2Dir=C:\Users\vagrant\dmd.`~ver~`.windows\dmd2'`~
                ` '/DVersion2=`~ver~`' d2-installer.nsi`);
            cmd(`move dmd-`~ver~`.exe C:\Users\vagrant\dmd-`~ver~`.exe`);
            // sign installer
            cmd(`&C:\Users\vagrant\codesign\sign.ps1 C:\Users\vagrant\codesign\win.pfx C:\Users\vagrant\codesign\win.fingerprint C:\Users\vagrant\codesign\win.pass C:\Users\vagrant\dmd-`~ver~`.exe`);
        }
        box.scp("default:dmd-"~ver~".exe", "build/");
        break;

    case OS.osx:
        with (box.shell())
        {
            cmd(`cp dmd.`~ver~`.osx.zip clones/installer/osx`);
            cmd(`cd clones/installer/osx`);
            cmd(`make dmd.`~ver~`.dmg VERSION=`~ver);
        }
        box.scp("'default:clones/installer/osx/*.dmg'", "build/");
        break;
    }
}

import std.regex;
enum versionRE = regex(`^v(\d+)\.(\d+)\.(\d+)(-.*)?$`);

string getDubTag(bool preRelease)
{
    import std.net.curl : get;
    import std.json : parseJSON;

    // github already sorts tags in descending semantic versioning order
    foreach (tag; get("https://api.github.com/repos/dlang/dub/tags").parseJSON.array)
        if (auto m = tag["name"].str.match(versionRE))
            if (preRelease || m.captures[4].empty)
                return tag["name"].str;
    throw new Exception("Failed to get dub tags");
}

void getCodesignCerts(string tgtDir)
{
    import std.base64;

    mkdirRecurse(tgtDir);

    foreach (entry; runCapture("pass ls dlang/codesign/")
        .lineSplitter
        .map!(ln => ln.findSplitAfter("── ")) // tree(1) entries
        .filter!(parts => !parts[0].empty)
        .map!(parts => parts[1]))
    {
        writeln("Copying codesign cert " ~ entry ~ " from passwordstore to " ~ tgtDir);
        auto content = runCapture("pass show dlang/codesign/"~entry);
        if (entry.endsWith(".b64"))
            std.file.write(tgtDir ~ "/" ~ entry[0 .. $ - ".b64".length], Base64.decode(content));
        else
            std.file.write(tgtDir ~ "/" ~ entry, content);
    }

    foreach (de; dirEntries(tgtDir, "*.pfx", SpanMode.shallow))
    {
        writeln("Getting fingerprint for codesign cert " ~ de.name);
        auto content = runCapture(
            "openssl pkcs12 -in "~escapeShellFileName(de.name)~" -nodes"~
              " -password file:"~escapeShellFileName(de.name.setExtension(".pass"))~
            "| openssl x509 -noout -fingerprint"
        );
        // SHA1 Fingerprint=BD:E0:0F:CA:EF:6A:FA:37:15:DB:D4:AA:1A:43:2E:78:27:54:E6:60 =>
        // BDE00FCAEF6AFA3715DBD4AA1A432E782754E660
        enforce(content.startsWith("SHA1 Fingerprint="), "Unexpected openssl fingerprint output:\n"~content);
        std.file.write(de.name.setExtension(".fingerprint"),
            content["SHA1 Fingerprint=".length .. $].replace(":", ""));
    }
}

void cloneSources(string gitTag, string dubTag, bool isBranch, bool skipDocs, string tgtDir)
{
    auto prefix = "https://github.com/dlang/";
    auto fmt = "git clone --depth 1 --branch %1$s " ~ prefix ~ "%2$s.git " ~ tgtDir ~ "/%2$s";
    size_t nfallback;
    foreach (proj; allProjects)
    {
        if (skipDocs && proj == "dlang.org")
            continue;
        // use master as fallback for feature branches
        if (isBranch && !branchExists(prefix ~ proj, gitTag))
        {
            ++nfallback;
            run(fmt.format("master", proj));
        }
        else
            run(fmt.format(gitTag, proj));
    }
    enforce(nfallback < allProjects.length, "Branch " ~ gitTag ~ " not found in any dlang repo.");
    run(fmt.format(dubTag, "dub"));
}

bool branchExists(string gitRepo, string branch)
{
    switch (runStatus("git ls-remote --heads --exit-code " ~ gitRepo ~ " " ~ branch))
    {
    case 0: return true;
    case 2: return false;
    default: throw new Exception("Failed to ls-remote " ~ gitRepo ~ " " ~ branch);
    }
}

void applyPatches(string gitTag, bool skipDocs, string tgtDir)
{
    auto fmt = "git -C "~tgtDir~"/%1$s apply -3 < patches/%1$s.patch";
    if (!"patches".exists)
        return;
    foreach (de; dirEntries("patches", "*.patch", SpanMode.shallow))
    {
        auto proj = de.baseName.stripExtension;
        if (skipDocs && proj == "dlang.org")
            continue;
        run(fmt.format(proj));
    }
}

auto lzmaExt = (OS os) => os == OS.windows ? ".7z" : ".tar.xz";

void lzmaArchives(string gitTag)
{
    auto baseName = "build/dmd."~gitTag~".";

    foreach (platform; platforms)
    {
        auto workDir = mkdtemp();
        scope (success) rmdirDirectoryNoFail(workDir);

        auto name = baseName ~ platform.toString;
        writeln("Building LZMA archive '", name~lzmaExt(platform.os), "'.");
        extractZip(name ~ ".zip", workDir);
        archiveLZMA(workDir~"/dmd2", name~lzmaExt(platform.os));
    }
}

int error(Args...)(string fmt, Args args)
{
    stderr.write("\033[031m");
    scope (exit) stderr.write("\033[0m");
    stderr.writefln(fmt, args);
    import core.stdc.stdlib : EXIT_FAILURE;
    return EXIT_FAILURE;
}

int main(string[] args)
{
    bool skipDocs = false;
    bool verifySignature = true;

    while (args.length > 3)
    {
        if (args[$-1] == "--skip-docs")
            skipDocs = true;
        else if (args[$-1] == "--skip-verify")
            verifySignature = false;
        else
            break;
        args = args[0..$-1];
    }
    if (args.length != 3)
        return error("Expected <old-dmd-version> <git-branch-or-tag> [--skip-docs] [--skip-verify] as arguments, e.g. 'rdmd build_all v2.066.0 v2.066.1'.");

    auto workDir = mkdtemp();
    scope (success) rmdirDirectoryNoFail(workDir);
    // Cache huge downloads
    enum cacheDir = "cached_downloads";

    auto oldVer = args[1];
    if (!oldVer.match(versionRE))
        return error("Expected a version tag like 'v2.066.0' not '%s'", oldVer);
    oldVer = oldVer.chompPrefix("v");

    immutable gitTag = args[2];
    auto verMatch = gitTag.match(versionRE);
    immutable isBranch = !verMatch;
    immutable isPreRelease = isBranch || !verMatch.captures[4].empty;
    immutable dubTag = getDubTag(isPreRelease);

    enum optlink = "optlink.zip";
    enum libC = "snn.lib";
    enum libCurl = "libcurl-7.68.0-WinSSL-zlib-x86-x64.zip";
    enum omflibs = "omflibs-winsdk-10.0.16299.15.zip";
    enum mingwtag = "mingw-libs-7.0.0-2";
    enum mingwlibs = mingwtag ~ ".zip";               enum mingw_sha = hexString!"ae9f991a64b17b2a6c9e5bd9f91f88a8ac3065194b0981be03be4280e2b6cc5a";
    enum lld = "lld-link-9.0.0-seh.zip";              enum lld_sha   = hexString!"ffde2eb0e0410e6985bbbb44c200b21a2b2dd34d3f8c3411f5ca5beb7f67ba5b";
    enum lld64 = "lld-link-9.0.0-seh-x64.zip";        enum lld64_sha = hexString!"c24f9b8daf7ec49c7bfb96d7c0de4e3ced76f9777114f7601bdd4185a2cc7338";
    enum ldc = "ldc2-"~ldcVer~"-windows-multilib.7z"; enum ldc_sha   = hexString!"7e4300fd6064305b2e7c2ff312283cefddbbe63eb1c36c551495f3df39f62000";

    auto oldCompilers = platforms
        .map!(p => "dmd.%1$s.%2$s.%3$s".format(oldVer, p, p.os == OS.windows ? "7z" : "tar.xz"));

    if (!isBranch)
        getCodesignCerts(workDir~"/codesign");
    foreach (url; oldCompilers.map!(s => "http://downloads.dlang.org/releases/2.x/"~oldVer~"/"~s))
        fetchFile(url, cacheDir~"/"~baseName(url), verifySignature);
    fetchFile("http://ftp.digitalmars.com/"~optlink, cacheDir~"/"~optlink);
    fetchFile("http://ftp.digitalmars.com/"~libC, cacheDir~"/"~libC);
    fetchFile("http://downloads.dlang.org/other/"~libCurl, cacheDir~"/"~libCurl, verifySignature);
    fetchFile("http://downloads.dlang.org/other/"~omflibs, cacheDir~"/"~omflibs, verifySignature);
    fetchFile("http://downloads.dlang.org/other/"~lld, cacheDir~"/"~lld, verifySignature, lld_sha);
    fetchFile("http://downloads.dlang.org/other/"~lld64, cacheDir~"/"~lld64, verifySignature, lld64_sha);
    fetchFile("https://github.com/dlang/installer/releases/download/"~mingwtag~"/"~mingwlibs, cacheDir~"/"~mingwlibs, verifySignature, mingw_sha);
    if (!ldcVer.empty)
        fetchFile("https://github.com/ldc-developers/ldc/releases/download/v"~ldcVer~"/"~ldc, cacheDir~"/"~ldc, verifySignature, ldc_sha);

    // Unpack previous dmd release
    foreach (platform, oldCompiler; platforms.zip(oldCompilers))
        extract(cacheDir~"/"~oldCompiler, workDir~"/"~platform.toString~"/old-dmd");

    if (platforms.canFind!(p => p.os == OS.windows))
    {
        // Use latest optlink to build release
        if (exists(workDir~"/windows/old-dmd/dmd2/windows/bin/link.exe"))
            remove(workDir~"/windows/old-dmd/dmd2/windows/bin/link.exe");
        if (exists(workDir~"/windows/old-dmd/dmd2/windows/bin/optlink.exe"))
            remove(workDir~"/windows/old-dmd/dmd2/windows/bin/optlink.exe");
        extract(cacheDir~"/"~optlink, workDir~"/windows/old-dmd/dmd2/windows/bin/");
        // Use latest libC (snn.lib) to build release
        remove(workDir~"/windows/old-dmd/dmd2/windows/lib/snn.lib");
        copyFile(cacheDir~"/"~libC, workDir~"/windows/old-dmd/dmd2/windows/lib/"~libC);
    }

    cloneSources(gitTag, dubTag, isBranch, skipDocs, workDir~"/clones");
    immutable dmdVersion = workDir~"/clones/dmd/VERSION";
    if (isBranch)
    {
        auto commit = runCapture("git -C "~workDir~"/clones/dmd rev-parse --short HEAD");
        std.file.write(dmdVersion, readText(dmdVersion).strip~"-"~gitTag~"-"~commit);
    }
    else
    {
        immutable dmdVer = std.file.readText(dmdVersion).stripRight;
        enforce(dmdVer == gitTag,
                "Mismatch between dmd/VERSION: '"~dmdVer~"' and git tag: '"~gitTag~"'.");
    }
    applyPatches(gitTag, skipDocs, workDir~"/clones");

    // copy weird custom binaries from the previous release
    prepareExtraBins(workDir);
    // add latest optlink
    extract(cacheDir~"/"~optlink, workDir~"/windows/extraBins/dmd2/windows/bin/");
    if (exists(workDir~"/windows/extraBins/dmd2/windows/bin/link.exe"))
        remove(workDir~"/windows/extraBins/dmd2/windows/bin/link.exe");
    // add latest dmc libC (snn.lib)
    copyFile(cacheDir~"/"~libC, workDir~"/windows/extraBins/dmd2/windows/lib/"~libC);
    // add libcurl build for windows
    extract(cacheDir~"/"~libCurl, workDir~"/windows/extraBins/");
    // add updated OMF import libraries
    extract(cacheDir~"/"~omflibs, workDir~"/windows/extraBins/dmd2/windows/lib/");
    // add mingw coff libraries
    extract(cacheDir~"/"~mingwlibs, workDir~"/windows/extraBins/");
    // add lld linker
    extract(cacheDir~"/"~lld, workDir~"/windows/extraBins/dmd2/windows/bin/");
    extract(cacheDir~"/"~lld64, workDir~"/windows/extraBins/dmd2/windows/bin64/");
    // add ldc compiler
    extract(cacheDir~"/"~ldc, workDir~"/windows/ldc/");

    immutable ver = gitTag.chompPrefix("v");
    mkdirRecurse("build");

    version (NoVagrant) version(linux) {} else
        if (!skipDocs)
            copyDirectory("docs", workDir);

    foreach (p; platforms)
    {
        with (Box(p))
        {
            auto src = [platform~"/old-dmd", "clones", osS~"/extraBins"];
            if (os == OS.windows) src ~= platform~"/ldc";
            auto toCopy = src.addPrefix(workDir~"/").join(" ");
            scp(toCopy, "default:");
            if (os != OS.linux && !skipDocs) scp(workDir~"/docs", "default:");
            // copy create_dmd_release.d and dependencies
            scp("create_dmd_release.d common.d", "default:");
            if (!isBranch)
                scp(workDir~"/codesign codesign", "default:");

            build(ver, isBranch, skipDocs);
            if (os == OS.linux && !skipDocs) scp("default:docs", workDir);
        }
    }
    lzmaArchives(ver);
    return 0;
}
