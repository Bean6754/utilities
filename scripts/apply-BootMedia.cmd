@echo off
rem **************************************************************************
rem ** Copyright (c) Microsoft Open Technologies, Inc.  All rights reserved.  
rem ** Licensed under the BSD 2-Clause License.  
rem ** See License.txt in the project root for license information.
rem **************************************************************************

rem **************************************************************************
rem ** apply-BootMedia.cmd
rem **************************************************************************

    setlocal enableextensions enabledelayedexpansion
    echo.

    set infoPrefix=****
    set errorPrefix=%infoPrefix% ERROR:

    rem **********************************************************************
    rem ** Display help if requested
    rem **********************************************************************
    if /i '%1' == '' goto :printHelpAndExit
    if /i '%1' == '-help' goto :printHelpAndExit
    if /i '%1' == '/help' goto :printHelpAndExit
    if /i '%1' == '-?' goto :printHelpAndExit
    if /i '%1' == '/?' goto :printHelpAndExit

    set /a status=0
    set cleanExit=:cleanExit

    rem **********************************************************************
    rem ** We need to create the image in context of 'Pacific Standard Time'
    rem **********************************************************************

    echo %infoPrefix% Temporarily changing time zone to 'Pacific Standard Time'
    rem %infoPrefix% Fat32 is local time based, and the images are created in a pacific time zone.
    rem %infoPrefix% If there is a mismatch Windows will bug check after 5 minutes.
    set originalTimeZone=
    call :GetCurrentTimeZone originalTimeZone
    if errorlevel 1 (
        echo %errorPrefix% Failed to determine current Time Zone.
        set /a status=-1
        goto %cleanExit%
    )
    tzutil.exe /s "Pacific Standard Time"
    if errorlevel 1 (
        echo %errorPrefix% Failed to set current Time Zone to 'Pacific Standard Time'.
        set /a status=-1
        goto %cleanExit%
    )
    set cleanExit=:restoreTimeZoneAndExit
    
    rem **********************************************************************
    rem ** Figure out the folder where this script is located (kitFolder)
    rem **********************************************************************

    call :GetPath "%~f0" kitFolder
    if not exist "%kitFolder%\%~n0%~x0" (
        echo %errorPrefix% Failed to determine kit folder
        set /a status=-1
        goto %cleanExit%
    )

    set instance=%RANDOM%
    set adminPassword=p%RANDOM%
    set sourceImage=
    set imageHostname=GALILEOPC-%instance%
    set applyFolder=

    rem **********************************************************************
    rem ** Process arguments
    rem **********************************************************************
    echo.
    echo %infoPrefix% Processing Arguments
    call :ProcessArgList %1 %2 %3 %4 %5 %6 %7 %8 %9
    if errorlevel 1 (
        set /a status=-1
        goto %cleanExit%
    )

    rem **********************************************************************
    rem ** Validate image filename
    rem **********************************************************************

    echo.
    echo %infoPrefix% Validating image filename
    echo %infoPrefix% This will fail if your path to the wim contains spaces.
    echo %infoPrefix% The error will contain "was unexpected at this time"
    if '%sourceImage%' == '' (
        call :GetLatestFile "%kitFolder%" *.WIM sourceImage
        if errorlevel 1 (
            echo %errorPrefix% Image must be specified or exist in script folder. [%kitFolder%]
            set /a status=-1
            goto %cleanExit%
        )
    )
    
    call :ExpandPath "%sourceImage%" sourceImage
    if not exist "%sourceImage%" (
        echo %errorPrefix% Cannot find/access the image specified. [%sourceImage%]
        set /a status=-1
        goto %cleanExit%
    )
    
    rem **********************************************************************
    rem ** Validate destination folder
    rem **********************************************************************

    echo.
    echo %infoPrefix% Validating destination folder
    call :ExpandPath "%applyFolder%" applyFolder
    call :NormalizeFilename "%applyFolder%" applyFolder
    if '%applyFolder%' == '' (
        echo %errorPrefix% Folder to apply the image is not specified...
        set /a status=-1
        goto %cleanExit%
    )

    if not exist %applyFolder% (
        echo %errorPrefix% Cannot find/access the destination path specified. [%applyFolder%]
        set /a status=-1
        goto %cleanExit%
    )

    call :VerifyEmptyFolder %applyFolder%
    if errorlevel 1 (
        echo %errorPrefix% Destination folder must be empty. [%applyFolder%]
        set /a status=-1
        goto %cleanExit%
    )
    
    rem **********************************************************************
    rem ** Set-up the folder to store temp files and set it as current
    rem **********************************************************************

    call :ExpandPath "%TEMP%" workFolder
    set workFolder=%workFolder%\%~n0-%instance%
    rd /s /q "%workFolder%" > nul 2>&1
    mkdir "%workFolder%"
    pushd "%workFolder%"
    if errorlevel 1 (
        echo %errorPrefix% Failed to set-up work folder '%workFolder%'
        set /a status=-1
        goto %cleanExit%
    )
    echo %infoPrefix% Set-up work folder: %workFolder%
    set TMP=%workFolder%
    set TEMP=%workFolder%
    set cleanExit=:popdAndExit

    rem **********************************************************************
    rem ** Retrieve image
    rem **********************************************************************

    echo %infoPrefix% Retrieveing %sourceImage%
    echo %infoPrefix%          to %workFolder%

    xcopy /v /j /r /y /g "%sourceImage%" "%workFolder%"\ > nul
    if errorlevel 1 (
        echo %errorPrefix% Failed to copy image %sourceImage%
        echo %errorPrefix%                   to %workFolder%
        set /a status=-1
        goto %cleanExit%
    )
    call :GetFilename "%sourceImage%" workImage

    rem **********************************************************************
    rem ** Mount image for customization
    rem **********************************************************************

    rmdir /s /q "%workFolder%\%workImage%.mount" > nul 2>&1
    mkdir "%workFolder%\%workImage%.mount"
    if errorlevel 1 (
        echo %errorPrefix% Failed to create empty mounting folder '%workFolder%\%workImage%.mount'
        set /a status=-1
        goto %cleanExit%
    )

    "%SystemRoot%\System32\Dism.exe" /Mount-Image /ImageFile:"%workFolder%\%workImage%" /MountDir:"%workFolder%\%workImage%.mount"\ /index:1
    if not !errorlevel! == 0 (
        echo %errorPrefix% Failed to mount image %workFolder%\%workImage%
        echo %errorPrefix%                    to %workFolder%\%workImage%.mount
        set /a status=-1
        goto %cleanExit%
    )

    call :CustomizeMountedImage
    if errorlevel 1 (
        echo %errorPrefix% Failed to customize image %workFolder%\%workImage%
        echo %errorPrefix%                mounted at %workFolder%\%workImage%.mount
        "%SystemRoot%\System32\Dism.exe" /Unmount-Image /MountDir:"%workFolder%\%workImage%.mount"\ /discard
        if not !errorlevel! == 0 (
            echo %errorPrefix% Failed to unmount '%workFolder%\%workImage%.mount'. You may have to do it manually...
        )
        set /a status=-1
        goto %cleanExit%
    )

    "%SystemRoot%\System32\Dism.exe" /Unmount-Image /MountDir:"%workFolder%\%workImage%.mount"\ /commit
    if not !errorlevel! == 0 (
        echo %errorPrefix% Failed to unmount '%workFolder%\%workImage%.mount'. You may have to do it manually...
        set /a status=-1
        goto %cleanExit%
    )

    rem **********************************************************************
    rem ** Apply image to specified folder
    rem **********************************************************************

    echo %infoPrefix% Applying image %workFolder%\%workImage%
    echo %infoPrefix%             to %applyFolder%

    "%SystemRoot%\System32\Dism.exe" /Apply-Image /ImageFile:"%workFolder%\%workImage%" /Index:1 /ApplyDir:%applyFolder%
    if not !errorlevel! == 0 (
        echo %errorPrefix% Failed to apply image %workFolder%\%workImage%
        echo %errorPrefix%             to folder %applyFolder%
        set /a status=-1
        goto %cleanExit%
    )

    rem **********************************************************************
    rem ** Load SYSTEM registry hive
    rem **********************************************************************

    set regRootKey=Galileo-%instance%-SYSTEM
    echo %infoPrefix% Mounting %applyFolder%\Windows\System32\config\SYSTEM
    echo %infoPrefix%       to HKEY_USERS\%regRootKey%
    reg load HKU\%regRootKey% %applyFolder%\Windows\System32\config\SYSTEM > nul
    if errorlevel 1 (
        echo %errorPrefix% Failed to load registry hive '%applyFolder%\Windows\System32\config\SYSTEM'
        set /a status=-1
        goto %cleanExit%
    )
    set cleanExit=:regUnloadAndExit

    rem **********************************************************************
    rem ** Set network name
    rem **********************************************************************

    echo %infoPrefix% Setting hostname to %imageHostname%

    reg add "HKU\%regRootKey%\ControlSet001\Services\Tcpip\Parameters" /v "HostName" /t REG_SZ /d %imageHostname% /f > nul
    if errorlevel 1 (
        echo %errorPrefix% Failed to update 'ControlSet001\Services\Tcpip\Parameters\HostName'
        set /a status=-1
        goto %cleanExit%
    )

    reg add "HKU\%regRootKey%\ControlSet001\Services\Tcpip\Parameters" /v "NV HostName" /t REG_SZ /d %imageHostname% /f > nul
    if errorlevel 1 (
        echo %errorPrefix% Failed to update 'ControlSet001\Services\Tcpip\Parameters\NV HostName'
        set /a status=-1
        goto %cleanExit%
    )

    reg add "HKU\%regRootKey%\ControlSet001\Control\ComputerName\ComputerName" /v "ComputerName" /t REG_SZ /d %imageHostname% /f > nul
    if errorlevel 1 (
        echo %errorPrefix% Failed to update 'ControlSet001\Control\ComputerName\ComputerName\ComputerName'
        set /a status=-1
        goto %cleanExit%
    )

    reg add "HKU\%regRootKey%\ControlSet001\Control\ComputerName\ActiveComputerName" /v "ComputerName" /t REG_SZ /d %imageHostname% /f > nul
    if errorlevel 1 (
        echo %errorPrefix% Failed to update 'ControlSet001\Control\ComputerName\ActiveComputerName\ComputerName'
        set /a status=-1
        goto %cleanExit%
    )

    rem **********************************************************************
    rem ** Schedule change of Administrator password on the first boot
    rem **********************************************************************

    echo @net user Administrator %adminPassword% >> %applyFolder%\Windows\System32\Boot\runonce.cmd

    rem **********************************************************************
    rem ** Done.
    rem **********************************************************************

    goto %cleanExit%

:regUnloadAndExit
    reg unload HKU\%regRootKey% > nul
    if errorlevel 1 (
        echo %errorPrefix% Failed to unload 'HKU\%regRootKey%'. You may have to do it manually...
    )

:restoreTimeZoneAndExit
    echo %infoPrefix% Restoring time zone to '%originalTimeZone%'
    tzutil.exe /s "%originalTimeZone%"
    if errorlevel 1 (
        echo %errorPrefix% Failed to restore Time Zone to '%originalTimeZone%'. You may have to do it manually...
    )

:popdAndExit
    popd
    rd /s /q "%workFolder%" > nul

:cleanExit
    if %status% == 0 (
        echo %infoPrefix%
        echo %infoPrefix%   Successfully applied %sourceImage%
        echo %infoPrefix%                     to %applyFolder%
        echo %infoPrefix%
        echo %infoPrefix%              hostname: %imageHostname%
        echo %infoPrefix%              timezone: %timeZone%
        echo %infoPrefix%              Username: Administrator
        echo %infoPrefix%              Password: %adminPassword%
        echo %infoPrefix%
    )

    if %status% == 0 (
        echo %infoPrefix% Done.
    ) else (
        echo %errorPrefix% Failed with status: %status%
    )
    exit /b %status%

:printHelpAndExit
    echo %infoPrefix%
    echo %infoPrefix% Applies Galileo (Quark) bootable image to specified media...
    echo %infoPrefix%
    echo %infoPrefix% %~n0 {-destination 'destination_path'} [-image 'image_filename'] [-hostname 'network_name'] [-password 'password']
    echo %infoPrefix%
    echo %infoPrefix%   'destination_path'  Path to the distination (e.g. SD card) to
    echo %infoPrefix%                       apply the image. NOTE: It must be empty
    echo %infoPrefix%                       (e.g SD cart must be formatted)
    echo %infoPrefix%
    echo %infoPrefix%   'image_filename'    Name of the WIM image to apply.
    echo %infoPrefix%                       If no -image switch specified script
    echo %infoPrefix%                       will use latest image located in the
    echo %infoPrefix%                       same folder as script itself
    echo %infoPrefix%
    echo %infoPrefix%   'network_name'      Desired network name for the image.
    echo %infoPrefix%
    echo %infoPrefix%   'password'          Desired password for Administrator. Random
    echo %infoPrefix%                       password will be generated by default.
    echo %infoPrefix%
    echo %infoPrefix% Examples:
    echo %infoPrefix%
    echo %infoPrefix%   %~n0 -image \\MY_BUILDS\LATEST\image.WIM -destination S:\
    echo %infoPrefix%     applies specified image onto S:\
    echo %infoPrefix%
    echo %infoPrefix%   %~n0 -image \\MY_BUILDS\LATEST\image.WIM -destination S:\ -hostname MY_GALILEO
    echo %infoPrefix%     prepares based on specified image and hostname MY_GALILEO
    echo %infoPrefix%
    exit /b 1

rem **************************************************************************
rem ** ProcessArgList - iterates the arguments list
rem **************************************************************************

:ProcessArgList
    if '%1' == '' exit /b 0

    if /i '%1' == '-image' goto :processArgImage
    if /i '%1' == '/image' goto :processArgImage

    if /i '%1' == '-hostname' goto :processArgHostname
    if /i '%1' == '/hostname' goto :processArgHostname

    if /i '%1' == '-destination' goto :processArgDestination
    if /i '%1' == '/destination' goto :processArgDestination

    if /i '%1' == '-password' goto :processArgPassword
    if /i '%1' == '/password' goto :processArgPassword

    echo %errorPrefix% Unknown/unexpected argument. [%1]
    exit /b 1

:processArgListNext
    shift
    goto :ProcessArgList

:processArgImage
    echo Processing Image Argument
    shift
    if '%1' == '' (
        echo %errorPrefix% Path to valid Windows build must be specified after '-image'.
        exit /b 1
    ) else if not exist "%~f1" (
        echo %errorPrefix% Cannot find/access the build path specified. [%~f1]
        exit /b 1
    )
    set sourceImage=%~f1
    goto :processArgListNext

:processArgDestination
    echo Processing Destination Argument
    shift
    if '%1' == '' (
        echo %errorPrefix% Destination of the target image must be specified after '-destination'.
        exit /b 1
    )
    call :ExpandPath "%~f1" applyFolder
    if '%applyFolder%' == '' (
        echo %errorPrefix% Invalid apply destination specified '%1'
        exit /b 1
    )
    goto :processArgListNext

:processArgHostname
    echo Processing Hostname Argument
    shift
    if '%1' == '' (
        echo %errorPrefix% Hostname must be specified after '-hostname'.
        exit /b 1
    ) else (
        set imageHostname=%1
    )
    goto :processArgListNext

:processArgPassword
    echo Processing Password Argument
    shift
    if '%1' == '' (
        echo %errorPrefix% Desired password must be specified after '-password'.
        exit /b 1
    )
    set adminPassword=%1
    goto :processArgListNext

rem **************************************************************************
rem ** CustomizeMountedImage - performs customization of image mounted
rem ** at "%workFolder%\%workImage%.mount".
rem **********************************************************************

:CustomizeMountedImage
    echo %infoPrefix% Customizing image %workFolder%\%workImage%
    echo %infoPrefix%        mounted at %workFolder%\%workImage%.mount

rem **********************************************************************
rem ** Apply current Time Zone to the image
rem **********************************************************************

    call :GetCurrentTimeZone timeZone
    if errorlevel 1 (
        echo %errorPrefix% Failed to determine current Time Zone.
        exit /b 1
    )

    "%SystemRoot%\System32\Dism.exe" /Image:"%workFolder%\%workImage%.mount"\ /Set-TimeZone:"%timeZone%" > nul
    if not !errorlevel! == 0 (
        echo %errorPrefix% Failed to set Time Zone '%timeZone'
        echo %errorPrefix%    for image mounted at %workFolder%\%workImage%.mount
        exit /b 1
    )

    exit /b 0

rem **************************************************************************
rem ** GetPath - returns parent folder path to specified file or folder
rem **  %1 - file or folder
rem **  %2 - name of the variable to return the parent folder path
rem **************************************************************************

:GetPath
    call :ExpandPath "%~d1%~p1" %2
    goto :EOF

rem **************************************************************************
rem ** ExpandPath - returns fully expanded name to specified file or folder
rem **  %1 - file or folder
rem **  %2 - name of the variable to return fully expanded name
rem **************************************************************************

:ExpandPath
    set %2=%~f1
    goto :EOF

rem **************************************************************************
rem ** GetFilename - return just a name of the file (without a path)
rem **  %1 - full/partial file name and path
rem **  %2 - name of the vaiable to return filename
rem **************************************************************************

:GetFilename
    set %2=%~n1%~x1
    goto :EOF

rem **************************************************************************
rem ** GetLatestFile - returns file in the specified folder
rem ** with latest creation date
rem **  %1 - path to parent folder
rem **  %2 - filename filter (e.g. *.TXT)
rem **  %3 - name of the variable to return subfolder
rem **************************************************************************

:GetLatestFile
    for /F "delims= usebackq" %%i in (`dir /b /o:-d "%~1\%~2"`) do (
        if not '%%i'=='' (
            call :ExpandPath "%~1\%%i" %3
            exit /b 0
        )
    )
    exit /b 1

rem **************************************************************************
rem ** VerifyEmptyFolder - Will succeed if specified folder is empty
rem **  %1 - folder to verify
rem **************************************************************************

:VerifyEmptyFolder
    for /F "delims= usebackq" %%i in (`dir /a /b "%~1"`) do (
        if not '%%i' == '' if not "%%i" == "System Volume Information" exit /b 1
    )
    exit /b 0

rem **************************************************************************
rem ** NormalizeFilename - Will remove "" from filename that doesn't these
rem **  %1 - Filename to normalize
rem **  %2 - name of the variable to return normalized filename
rem **************************************************************************

:NormalizeFilename
    call :_NormalizeFilenameVerifyNoSpaces %~1
    if errorlevel 1 (
        set %2="%~1"
    ) else (
        set %2=%~1
    )
    exit /b 0
:_NormalizeFilenameVerifyNoSpaces
    if '%2' == '' exit /b 0
    exit /b 1

rem **************************************************************************
rem ** GetCurrentTimeZone - Returns text descriptor of the current time zone
rem **  %1 - name of the variable to return the descriptor
rem **************************************************************************

:GetCurrentTimeZone
    for /F "delims= usebackq" %%i in (`tzutil.exe /g`) do (
        if not '%%i'=='' (
            set %1=%%i
            exit /b 0
        )
    )
    exit /b 1

