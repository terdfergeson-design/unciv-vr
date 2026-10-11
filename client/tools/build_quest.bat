@echo off
rem Builds the standalone Quest app: build\UncivVR-Quest.apk (next to client and unciv).
rem   tools\build_quest.bat            build it
rem   tools\build_quest.bat install    build it, then install it on the Quest over USB (adb)
rem Needs: the Android SDK (Android Studio, with Command-line Tools), a JDK 17+ for Unciv's gradle
rem (JAVA_HOME), Godot 4.7.2 with its export templates, and Godot's Editor Settings pointing at the SDK and
rem a JDK 17 (Export > Android). Set GODOT to Godot's exe if it isn't the one below.
setlocal
set ROOT=%~dp0..\..
pushd "%ROOT%" || exit /b 1
set ROOT=%CD%
if "%GODOT%"=="" set GODOT=%USERPROFILE%\Documents\Godot_v4.7.2-stable_win64.exe
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe

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
"%GODOT%" --headless --path client -s tools/pack_android_data.gd || goto fail

echo === 4. import
"%GODOT%" --headless --path client --import

echo === 5. export the APK
if not exist build mkdir build
set TEMPLATE=
if not exist "client\android\build\build.gradle" set TEMPLATE=--install-android-build-template
"%GODOT%" --headless --path client %TEMPLATE% --export-debug "Quest" "%ROOT%\build\UncivVR-Quest.apk"
if not exist "build\UncivVR-Quest.apk" goto fail
echo Built build\UncivVR-Quest.apk

if not "%1"=="install" goto done
echo === 6. install on the Quest
"%ADB%" install -r "build\UncivVR-Quest.apk" || goto fail

:done
popd
exit /b 0
:fail
echo FAILED
popd
exit /b 1
