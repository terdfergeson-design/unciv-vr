@echo off
rem Builds the standalone Quest app, into the build folder next to client and unciv.
rem   tools\build_quest.bat                   a debug build:  build\UncivVR-Quest.apk
rem   tools\build_quest.bat install           that, then installed on the Quest over USB (adb)
rem   tools\build_quest.bat release           a signed build to share: build\UncivVR-v<version>-quest.apk
rem   tools\build_quest.bat release install    that, then installed
rem
rem Needs: the Android SDK (Android Studio, with Command-line Tools), a JDK 17+ for Unciv's gradle (JAVA_HOME),
rem Godot 4.7.2 with its export templates, and Godot's Editor Settings pointing at the SDK and a JDK 17
rem (Export > Android). Set GODOT to Godot's exe if it isn't the one below.
rem
rem A release build is signed with your own keystore, which Godot finds through three environment variables.
rem Set them once, in a Command Prompt (setx only reaches windows opened afterwards):
rem    setx GODOT_ANDROID_KEYSTORE_RELEASE_PATH "C:\path\to\your.keystore"
rem    setx GODOT_ANDROID_KEYSTORE_RELEASE_USER "your-key-alias"
rem    setx GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD "your-password"
rem Keep the keystore outside this repository and back it up: every later update of the app has to be signed with
rem the same key, or the headset refuses to install it over the old one. The version in the name comes from
rem version/name in client\export_presets.cfg - bump that, and version/code, for each release you share.
setlocal
set ROOT=%~dp0..\..
pushd "%ROOT%" || exit /b 1
set ROOT=%CD%
if "%GODOT%"=="" set GODOT=%USERPROFILE%\Documents\Godot_v4.7.2-stable_win64.exe
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
set SDK=%LOCALAPPDATA%\Android\Sdk

set MODE=debug
set INSTALL=
if /i "%1"=="release" set MODE=release
if /i "%1"=="install" set INSTALL=yes
if /i "%2"=="install" set INSTALL=yes
if "%MODE%"=="release" goto release_setup
set APK=%ROOT%\build\UncivVR-Quest.apk
set EXPORT=--export-debug
goto start

:release_setup
set EXPORT=--export-release
rem The version comes from the export preset, so there's one place to bump it
for /f "tokens=2 delims==" %%v in ('findstr /b /c:"version/name=" client\export_presets.cfg') do set VERSION=%%~v
for /f "tokens=2 delims==" %%v in ('findstr /b /c:"version/code=" client\export_presets.cfg') do set VERSIONCODE=%%v
if not defined VERSION goto no_version
set APK=%ROOT%\build\UncivVR-v%VERSION%-quest.apk
echo Release %VERSION% (version code %VERSIONCODE%)
rem The key can come from the environment, or from the Godot editor (Project > Export > Quest > Keystore > Release),
rem which keeps it in client\.godot\export_credentials.cfg - and only writes that when the export window is closed,
rem so a key just typed in is not on disk yet and an export from here can't see it. That file belongs to the project
rem folder it was entered in, which is why a key set up in one checkout is missing in another.
if defined GODOT_ANDROID_KEYSTORE_RELEASE_PATH goto keystore_from_environment
if exist "client\.godot\export_credentials.cfg" goto keystore_from_editor
if exist "client\export_credentials.cfg" goto keystore_from_editor
findstr /c:"keystore/release=" client\export_presets.cfg >nul 2>&1
if not errorlevel 1 goto keystore_from_editor
echo No release keystore found. Either set GODOT_ANDROID_KEYSTORE_RELEASE_PATH, _USER and _PASSWORD (see the top
echo of this file), or fill in Project ^> Export ^> Quest ^> Keystore ^> Release in the Godot editor and close the
echo export window, so it writes them to disk. Carrying on - the export will say if it can't sign.
goto start

:keystore_from_editor
echo Signing with the keystore saved by the Godot editor.
goto start

:keystore_from_environment
if not exist "%GODOT_ANDROID_KEYSTORE_RELEASE_PATH%" goto no_keystore_file
echo Signing with %GODOT_ANDROID_KEYSTORE_RELEASE_PATH% (alias %GODOT_ANDROID_KEYSTORE_RELEASE_USER%)

:start
echo === 1. OpenXR vendors plugin (Meta)
if not exist "client\addons\godotopenxrvendors\plugin.gdextension" (
  echo The OpenXR vendors plugin is missing from client\addons\godotopenxrvendors - get it from git.
  goto fail
)

echo === 2. the bridge as an Android plugin
pushd unciv
call gradlew.bat :bridge-android:copyToClient --console=plain || (popd & goto fail)
popd

echo === 3. pack the game data
"%GODOT%" --headless --xr-mode off --path client -s tools/pack_android_data.gd || goto fail

echo === 4. import
"%GODOT%" --headless --xr-mode off --path client --import

echo === 5. export the app
if not exist build mkdir build
set TEMPLATE=
if not exist "client\android\build\build.gradle" set TEMPLATE=--install-android-build-template
del /q "%APK%" 2>nul
"%GODOT%" --headless --xr-mode off --path client %TEMPLATE% %EXPORT% "Quest" "%APK%"
if not exist "%APK%" goto no_apk
echo Built %APK%

if "%MODE%"=="debug" goto install_step
echo === 6. check how it was signed
set APKSIGNER=
for /f "delims=" %%d in ('dir /b /ad /o-n "%SDK%\build-tools" 2^>nul') do if not defined APKSIGNER set APKSIGNER=%SDK%\build-tools\%%d\apksigner.bat
if defined APKSIGNER call "%APKSIGNER%" verify --print-certs "%APK%" || goto fail
if not defined APKSIGNER echo No apksigner in %SDK%\build-tools - skipped the check.

:install_step
if not defined INSTALL goto done
echo === install on the Quest
rem A release build is signed with a different key than a debug one, so Android won't update one with the other:
rem uninstall the old app first if this fails (that deletes its saves, which live in the app's own storage).
"%ADB%" install -r "%APK%" || goto fail

:done
echo Done: %APK%
popd
exit /b 0

:no_version
echo Can't read version/name from client\export_presets.cfg
goto fail

:no_apk
echo Nothing was exported. For a release build that usually means the keystore: the message above says which part
echo Godot was unhappy with (missing file, wrong password, no such alias).
goto fail

:no_keystore_file
echo No keystore at %GODOT_ANDROID_KEYSTORE_RELEASE_PATH%
goto fail

:fail
echo FAILED
popd
exit /b 1
