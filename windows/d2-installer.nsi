; Release Manager:
;
; Preliminary instructions
; ------------------------
;
; Please use the special build of NSIS that supports large strings.
; Updating the PATH will often not work or work incorrectly with the
; regular build of NSIS.
;
; http://nsis.sourceforge.net/Special_Builds
;
;
; Instructions
; ------------
;
; Two defines must be set to use the installer:
; - EmbedD2Dir: The path to the directory tree recursively embedded in the
;               generated installer.
; - Version2:   The DMD version number.
;
; The easiest way is to use the /D command line options for makensis
;   makensis /DEmbedD2Dir=<some path> /DVersion2=2.xxx
;
; The Extras that are downloaded should be updated to use the latest versions.

;--------------------------------------------------------
; Defines
;--------------------------------------------------------

; Required
; --------
; EmbedD2Dir. Can be specified here rather than on the makensis command line:
;!define EmbedD2Dir "<path to files to install>"

; Version2. Can be specified here rather than on the makensis command line:
;!define Version2 "2.0xx"


; Routinely Update
; ----------------
; Visual D
!define VersionVisualD "0.3.40"

; DMC
!define VersionDMC "857"

; D1
!define Version1 "1.076"
!define Version1ReleaseYear "2013" ; S3 file hosting includes the year in the URL so update this as needed


; Update Rarely Needed
; --------------------
; Files
!define VisualDFilename "VisualD-v${VersionVisualD}.exe"
!define DmcFilename "dmc-${VersionDMC}.exe"
!define Dmd1Filename "dmd-${Version1}.exe"

; URLs
!define BaseURL "http://downloads.dlang.org"
!define BaseURLAlt "http://ftp.digitalmars.com"
!define VisualDBaseURL "https://github.com/D-Programming-Language/visuald/releases/download"

!define VisualDUrl "${VisualDBaseURL}/v${VersionVisualD}/${VisualDFilename}"

!define DmcUrl  "${BaseURL}/other/${DmcFilename}"
!define DmcAltUrl "${BaseURLAlt}/${DmcFilename}"

!define Dmd1Url "${BaseURL}/releases/${Version1ReleaseYear}/${Dmd1Filename}"
!define Dmd1AltUrl "${BaseURLAlt}/${Dmd1Filename}"

; Publishing Details
!define DPublisher "Digital Mars"
!define DName "DMD"
!define ARP "Software\Microsoft\Windows\CurrentVersion\Uninstall\${DName}"

; Version2 Fallback
; The version will be pulled from the VERSION file in the dmd repository if
; not specified with /D to makensis or defined above. Change the path to match.
!define D2VersionPath "..\..\dmd\VERSION"
!ifndef Version2
  !define /file Version2 ${D2VersionPath}
!endif


;--------------------------------------------------------
; Includes
;--------------------------------------------------------

!include "MUI.nsh"
!include "EnvVarUpdate.nsh"
!include "ReplaceInFile.nsh"
!include "FileFunc.nsh"


;------------------------------------------------------------
; Variables
;------------------------------------------------------------

Var I
Var J
Var K
Var InstanceCheck



;--------------------------------------------------------
; General definitions
;--------------------------------------------------------

; Name of the installer
Name "D Programming Language"

; Name of the output file of the installer
!define InstallerFilename "dmd-${Version2}.exe"
OutFile ${InstallerFilename}

; Where the program will be installed
InstallDir "C:\D"

; Take the installation directory from the registry, if possible
InstallDirRegKey HKCU "Software\${DName}" "InstallationFolder"

; This is so no one can corrupt the installer
CRCCheck force

SetCompressor /SOLID lzma


;------------------------------------------------------------
; Macros definition
;------------------------------------------------------------

; Check if a dmd installer instance is already running
!macro OneInstanceOnly
  System::Call 'kernel32::CreateMutexA(i 0, i 0, t "digital_mars_d_compiler_installer") ?e'
  Pop $R0
  StrCmp $R0 0 +3
    MessageBox MB_OK|MB_ICONSTOP "An instance of DMD installer is already running"
    Abort
!macroend


!macro DownloadAndRun Filename Url AltUrl
  inetc::get /CAPTION "Downloading ${Filename}..." /BANNER "" "${Url}" "$TEMP\${Filename}"
  Pop $0
  StrCmp $0 "OK" run
  !if `${AltUrl}` != ""
    inetc::get /CAPTION "Downloading ${Filename}..." /BANNER "" "${AltUrl}" "$TEMP\${Filename}"
    Pop $0
    StrCmp $0 "OK" run
  !endif

  ; failed
  MessageBox MB_OK|MB_ICONEXCLAMATION "Could not download ${Filename}$\r$\n$\r$\n${Url}"

  Goto dandr_done

  run:
  DetailPrint "Running ${Filename}"
  ExecWait "$TEMP\${Filename}"

  Delete "$TEMP\${Filename}"

  dandr_done:
!macroend


;--------------------------------------------------------
; Interface settings
;--------------------------------------------------------

; Confirmation when exiting the installer
!define MUI_ABORTWARNING

!define MUI_ICON "installer-icon.ico"
!define MUI_UNICON "uninstaller-icon.ico"


;--------------------------------------------------------
; Language selection dialog settings
;--------------------------------------------------------

; Remember the installation language
!define MUI_LANGDLL_REGISTRY_ROOT "HKCU"
!define MUI_LANGDLL_REGISTRY_KEY "Software\D"
!define MUI_LANGDLL_REGISTRY_VALUENAME "Installer Language"


;--------------------------------------------------------
; Installer pages
;--------------------------------------------------------

!define MUI_WELCOMEFINISHPAGE_BITMAP "d2-installer-image.bmp"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH


;--------------------------------------------------------
; The languages
;--------------------------------------------------------

!insertmacro MUI_LANGUAGE "English"


; Reserve files needed by the installation
!insertmacro MUI_RESERVEFILE_LANGDLL


;--------------------------------------------------------
; Sections
;--------------------------------------------------------

SectionGroup /e "D2"
  Section "-D2" Dmd2Files
    ; This section is mandatory
    SectionIn RO

    SetOutPath $INSTDIR
    CreateDirectory "$INSTDIR"

    ; Embed the directory specified
    File /r ${EmbedD2Dir}

    ; Create 32-bit command line batch file
    FileOpen $0 "$INSTDIR\dmd2vars32.bat" w
    FileWrite $0 "@echo.$\n"
    FileWrite $0 "@echo Setting up 32-bit environment for using DMD 2 from %~dp0dmd2\windows\bin.$\n"
    FileWrite $0 "@set PATH=%~dp0dmd2\windows\bin;%PATH%$\n"
    FileClose $0

    ; Create 64-bit command line batch file
    FileOpen $0 "$INSTDIR\dmd2vars64.bat" w
    FileWrite $0 "@echo.$\n"
    FileWrite $0 "@echo Setting up 64-bit environment for using DMD 2 from %~dp0dmd2\windows\bin.$\n"
    FileWrite $0 "@echo.$\n"
    FileWrite $0 "@echo dmd must still be called with -m64 in order to generate 64-bit code.$\n"
    FileWrite $0 "@echo This command prompt adds the path of extra 64-bit DLLs so generated programs$\n"
    FileWrite $0 "@echo which use the extra DLLs (notably libcurl) can be executed.$\n"
    FileWrite $0 "@set PATH=%~dp0dmd2\windows\bin;%PATH%$\n"
    FileWrite $0 "@set PATH=%~dp0dmd2\windows\bin64;%PATH%$\n"
    FileClose $0

    ; Write installation dir in the registry
    WriteRegStr HKLM "SOFTWARE\${DName}" "InstallationFolder" "$INSTDIR"

    ; Registry keys for dmd uninstaller
    WriteRegStr HKLM "${ARP}" "DisplayName" "${DName}"
    WriteRegStr HKLM "${ARP}" "DisplayVersion" "${Version2}"
    WriteRegStr HKLM "${ARP}" "UninstallString" "$INSTDIR\uninstall.exe"
    WriteRegStr HKLM "${ARP}" "DisplayIcon" "$INSTDIR\uninstall.exe"
    WriteRegStr HKLM "${ARP}" "Publisher" "${DPublisher}"
    WriteRegStr HKLM "${ARP}" "HelpLink" "http://dlang.org/"
    WriteRegDWORD HKLM "${ARP}" "NoModify" 1
    WriteRegDWORD HKLM "${ARP}" "NoRepair" 1
    WriteUninstaller "uninstall.exe"
  SectionEnd


  Section "Detect MSVC" DetectMSVC
    ClearErrors

    ReadRegStr $0 HKLM "Software\Microsoft\VisualStudio\14.0\Setup\VC" "ProductDir"
    StrCpy $1 ";VC2015 "
    IfErrors 0 write_vc_path
    ClearErrors
    ReadRegStr $0 HKLM "Software\Microsoft\VisualStudio\12.0\Setup\VC" "ProductDir"
    StrCpy $1 ";VC2013 "
    IfErrors 0 write_vc_path
    ClearErrors
    ReadRegStr $0 HKLM "Software\Microsoft\VisualStudio\11.0\Setup\VC" "ProductDir"
    StrCpy $1 ";VC2012 "
    IfErrors 0 write_vc_path
    ClearErrors
    ReadRegStr $0 HKLM "Software\Microsoft\VisualStudio\10.0\Setup\VC" "ProductDir"
    StrCpy $1 ";VC2010 "
    IfErrors 0 write_vc_path
    ClearErrors
    ReadRegStr $0 HKLM "Software\Microsoft\VisualStudio\9.0\Setup\VC" "ProductDir"
    StrCpy $1 ";VC2008 "
    IfErrors no_vc_detected write_vc_path

    write_vc_path:
    !insertmacro _ReplaceInFile "$INSTDIR\dmd2\windows\bin\sc.ini" ";VCINSTALLDIR=" "VCINSTALLDIR=$0"
    !insertmacro _ReplaceInFile "$INSTDIR\dmd2\windows\bin\sc.ini" "$1" ""
    goto finish_vc_path

    no_vc_detected:
    MessageBox MB_OK "Could not detect Visual Studio (2008-2015 are supported). Using defaults."


    finish_vc_path:
    ClearErrors

    ReadRegStr $0 HKLM "Software\Microsoft\Windows Kits\Installed Roots" "KitsRoot10"
    IfErrors 0 write_sdk_path
    ClearErrors
    ReadRegStr $0 HKLM "Software\Microsoft\Windows Kits\Installed Roots" "KitsRoot81"
    IfErrors 0 write_sdk_path
    ClearErrors
    ReadRegStr $0 HKLM "Software\Microsoft\Windows Kits\Installed Roots" "KitsRoot" ; 8.0
    IfErrors 0 write_sdk_path
    ClearErrors
    ReadRegStr $0 HKLM "Software\Microsoft\Microsoft SDKs\Windows\v7.1A" "InstallationFolder"
    IfErrors 0 write_sdk_path
    ClearErrors
    ReadRegStr $0 HKLM "Software\Microsoft\Microsoft SDKs\Windows\v7.0A" "InstallationFolder"
    IfErrors 0 write_sdk_path
    ClearErrors
    ReadRegStr $0 HKLM "Software\Microsoft\Microsoft SDKs\Windows\v6.0A" "InstallationFolder"
    IfErrors no_sdk_detected write_sdk_path

    write_sdk_path:
    !insertmacro _ReplaceInFile "$INSTDIR\dmd2\windows\bin\sc.ini" ";WindowsSdkDir=" "WindowsSdkDir=$0"
    goto finish_sdk_path

    no_sdk_detected:
    MessageBox MB_OK "Could not detect Windows SDK (6.0A-10.0 are supported). Using defaults."


    finish_sdk_path:
    ClearErrors
  SectionEnd


  Section "Add to PATH" AddD2ToPath
    ${EnvVarUpdate} $0 "PATH" "A" "HKLM" "$INSTDIR\dmd2\windows\bin"
  SectionEnd


  Section "Start Menu" StartMenuShortcuts
    CreateDirectory "$SMPROGRAMS\D"

    CreateShortCut "$SMPROGRAMS\D\D2 HTML Documentation.lnk" "$INSTDIR\dmd2\html\d\index.html"
    CreateShortCut "$SMPROGRAMS\D\D2 Documentation.lnk" "$INSTDIR\dmd2\windows\bin\d.chm"
    CreateShortCut "$SMPROGRAMS\D\D2 32-bit Command Prompt.lnk" '%comspec%' '/k ""$INSTDIR\dmd2vars32.bat""' "" "" SW_SHOWNORMAL "" "Open D2 32-bit Command Prompt"
    CreateShortCut "$SMPROGRAMS\D\D2 64-bit Command Prompt.lnk" '%comspec%' '/k ""$INSTDIR\dmd2vars64.bat""' "" "" SW_SHOWNORMAL "" "Open D2 64-bit Command Prompt"
  SectionEnd
SectionGroupEnd


SectionGroup /e "Extras"
  Section /o "Download Visual D" VisualDDownload
    !insertmacro DownloadAndRun ${VisualDFilename} ${VisualDUrl} ""
  SectionEnd


  Section /o "Download DMC" DmcDownload
    !insertmacro DownloadAndRun ${DmcFilename} ${DmcUrl} ${DmcAltUrl}
  SectionEnd


  Section /o "Download D1" Dmd1Download
    !insertmacro DownloadAndRun ${Dmd1Filename} ${Dmd1Url} ${Dmd1AltUrl}
  SectionEnd
SectionGroupEnd


;--------------------------------------------------------
; Installer functions
;--------------------------------------------------------

Function .onInit
  ; Check if a dmd installer instance is already running
  !insertmacro OneInstanceOnly


  ; Force install without uninstall (useful if uninstall is broken)
  ${GetParameters} $R0
  StrCmp $R0 "/f" done


  ; Remove previous dmd installation if any
  ; this section is for previous dmd installer only
  ReadRegStr $R5 HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\D" "UninstallString"
  ReadRegStr $R6 HKLM "SOFTWARE\D" "Install_Dir"
  StrCmp $R5 "" done2
  MessageBox MB_OKCANCEL|MB_ICONQUESTION \
  "A previous DMD is installed on your system$\n$\nPress 'OK' to replace by ${DName} ${Version2}" \
  IDOK +2
  Abort
  ClearErrors
  ; Run uninstaller fron installed directory
  ExecWait '$R5 /S _?=$R6' $K
  ; Exit if uninstaller return an error
  IfErrors 0 +3
    MessageBox MB_OK|MB_ICONSTOP \
    "An error occurred when removing DMD$\n$\nRun '${InstallerFilename} /f' to force install ${DName} ${Version2}"
    Abort
  ; Remove in background the remaining uninstaller program itself
  Sleep 1000
  Exec '$R5 /S'
  ; MessageBox MB_OK|MB_ICONINFORMATION "Previous DMD uninstalled"

  done2:
  ; End of removing previous dmd installation section


  ; Remove if dmd is already installed
  ReadRegStr $R0 HKLM "${ARP}" "UninstallString"
  StrCmp $R0 "" done

  ReadRegStr $I HKLM "${ARP}" "DisplayName"
  ReadRegStr $J HKLM "${ARP}" "DisplayVersion"
  MessageBox MB_OKCANCEL|MB_ICONQUESTION \
  "$I v$J is installed on your system$\n$\nPress 'OK' to replace by ${DName} ${Version2}" \
  IDOK uninst
  Abort

  uninst:
    ClearErrors
    ; Run uninstaller from installed directory
    ExecWait '$R0 /IC False _?=$INSTDIR' $K
    ; Exit if uninstaller return an error
    IfErrors 0 +3
      MessageBox MB_OK|MB_ICONSTOP \
      "An error occurred when removing $I v$J$\n$\nRun '${InstallerFilename} /f' to force install ${DName} ${Version2}"
      Abort
    ; Exit if uninstaller is cancelled by user
    StrCmp $K 0 +2
      Abort
    ; Remove in background the remaining uninstaller program itself
    Exec '$R0 /IC False /S'

  done:
FunctionEnd


; Contains descriptions of components and other stuff
!include d2-installer-descriptions.nsh


;--------------------------------------------------------
; Uninstaller
;--------------------------------------------------------

Section "Uninstall"
  ; Remove directories from PATH (for all users)
  ${un.EnvVarUpdate} $0 "PATH" "R" "HKLM" "$INSTDIR\dmd2\windows\bin"

  ; Remove stuff from registry
  DeleteRegKey HKLM "${ARP}"
  DeleteRegKey HKLM "SOFTWARE\${DName}"

  ; Remove the uninstaller
  Delete $INSTDIR\uninstall.exe

  ; Remove the generated batch files
  Delete $INSTDIR\dmd2vars32.bat
  Delete $INSTDIR\dmd2vars64.bat

  ; Remove shortcuts
  Delete "$SMPROGRAMS\D\D2 HTML Documentation.lnk"
  Delete "$SMPROGRAMS\D\D2 Documentation.lnk"
  Delete "$SMPROGRAMS\D\D2 32-bit Command Prompt.lnk"
  Delete "$SMPROGRAMS\D\D2 64-bit Command Prompt.lnk"
  RMDir "$SMPROGRAMS\D"

  MessageBox MB_OKCANCEL|MB_ICONEXCLAMATION \
  "The uninstaller will now recursively delete ALL files and directories under '$INSTDIR\dmd2'. Continue?" \
  IDOK rmdir
  Abort

  rmdir:
  ; Remove used directories
  RMDir /r "$INSTDIR\dmd2"
  RMDir "$INSTDIR"
SectionEnd


;--------------------------------------------------------
; Uninstaller functions
;--------------------------------------------------------

Function un.onInit
  ; Check if a dmd installer instance is already running
  ; Do not check if "/IC False" argument is passed to uninstaller
  ${GetOptions} $CMDLINE "/IC" $InstanceCheck
  ${IfNot} "$InstanceCheck" == "False"
    !insertmacro OneInstanceOnly
  ${EndIf}
FunctionEnd

