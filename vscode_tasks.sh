#!/usr/bin/env bash

if [[ $# -eq 0 ]]; then
    echo "usage: [--debug|--release] [--clean] [--enable-cmake] [--setup-project] [--build] [--run]"
fi

cd "$(dirname "$0")"
THIS_DIR="$(pwd)"
PROJECT_DIR="$THIS_DIR"
ADB_COMMAND="$PROJECT_DIR/utils/adb_command.sh"

export PACKAGE_NAME="org.wysaid.cgeDemo"
export LAUNCH_ACTIVITY="MainActivity"
export GRADLEW_RUN_TASK="installDebug"
export ANDROID_BUILD_TYPE="assembleDebug"

if ! command -v cmd &>/dev/null && [[ -f "/mnt/c/Windows/system32/cmd.exe" ]]; then
    function cmd() {
        /mnt/c/Windows/system32/cmd.exe $@
    }
fi

function runGradleCommand() {
    if ! ./gradlew $@; then
        command -v cmd &>/dev/null && cmd /C gradlew $@
    fi
}

function setupProject() {
    if [[ -f "$PROJECT_DIR/local.properties" ]] && grep -E '^usingCMakeCompile=true' "$PROJECT_DIR/local.properties"; then
        echo "Using cmake, skip ndk build..."
    else
        bash "$PROJECT_DIR/library/src/main/jni/buildJNI" || exit 1
    fi
}

function runAndroidApp() {

    if . "$ADB_COMMAND" -d shell am start -n "$PACKAGE_NAME/$PACKAGE_NAME.$LAUNCH_ACTIVITY"; then
        if [[ -z "$(ps -ef | grep -i adb | grep -v grep | grep logcat)" ]]; then
            . "$ADB_COMMAND" -d logcat -c
            if [[ $(uname -s) == "Linux" ]] || [[ $(uname -s) == "Darwin" ]]; then
                APP_PROC_ID=$(. "$ADB_COMMAND" shell ps | grep org.wysaid.cgeDemo | tr -s ' ' | cut -d' ' -f2)
                if [[ -n "$APP_PROC_ID" ]]; then
                    . "$ADB_COMMAND" -d logcat | grep -F "$APP_PROC_ID"
                else
                    echo "Can not find proc id of org.wysaid.cgeDemo"
                fi
            else
                . "$ADB_COMMAND" -d logcat | grep -iE "(cge|demo|wysaid| E |crash)"
            fi
        fi
    else
        echo "Launch $PACKAGE_NAME/$PACKAGE_NAME.$LAUNCH_ACTIVITY failed."
    fi
}

function cleanProject() {
    runGradleCommand clean --refresh-dependencies
}

function buildProject() {
    if ! runGradleCommand -p cgeDemo "$ANDROID_BUILD_TYPE"; then

        echo "Failed to run: ./gradlew -p cgeDemo $ANDROID_BUILD_TYPE"
        echo "Please run the following command and try again:"
        echo "---"
        echo "$THIS_DIR/vscode_tasks.sh --setup-project"
        echo "---"
        exit 1
    fi

    GENERATED_APK_FILE=$(find "$THIS_DIR/cgeDemo/build" -iname "*.apk" | grep -i "${ANDROID_BUILD_TYPE/assemble/}")
    echo "apk generated at: $GENERATED_APK_FILE"

    if [[ -n "$GRADLEW_RUN_TASK" ]] && [[ $(. "$ADB_COMMAND" -d devices | grep -v 'List' | grep -vE '^$' | wc -l | tr -d ' ') -ne 0 ]]; then
        if [[ "$GRADLEW_RUN_TASK" == "installRelease" ]]; then
            # release can not be installed directly. do adb install.
            . "$ADB_COMMAND" -d install "$GENERATED_APK_FILE"
        else
            if ! runGradleCommand -p cgeDemo "$GRADLEW_RUN_TASK"; then
                echo "Install failed." >&2
            fi
        fi
    else
        echo "No device connected, skip installation."
    fi
}

if [[ ! -f "local.properties" ]]; then
    if [[ -n "$ANDROID_SDK_HOME" ]]; then
        echo "sdk.dir=$ANDROID_SDK_HOME" >>local.properties
    elif [[ -n "$ANDROID_SDK_ROOT" ]]; then
        echo "sdk.dir=$ANDROID_SDK_ROOT" >>local.properties
    elif [[ -n "$ANDROID_SDK" ]]; then
        echo "sdk.dir=$ANDROID_SDK" >>local.properties
    else
        echo "Can't find ANDROID_SDK, Please setup 'local.properties'" >&2
    fi
fi

function changeProperty() {
    TARGET_FILE="$1"
    MATCH_PATTERN="$2"
    SED_PATTERN="$3"
    DEFAULT_VALUE="$4"
    if [[ -f "$TARGET_FILE" ]] && grep -E "$MATCH_PATTERN" "$TARGET_FILE" >/dev/null; then
        # Stupid diff between the command.
        if [[ "$(uname -s)" == "Darwin" ]]; then # Mac OS
            sed -I "" -E "$SED_PATTERN" "$TARGET_FILE"
        else
            sed -i"" -E "$SED_PATTERN" "$TARGET_FILE"
        fi
    else
        echo "$DEFAULT_VALUE" >>"$TARGET_FILE"
    fi
}

while [[ $# > 0 ]]; do

    PARSE_KEY="$1"

    case "$PARSE_KEY" in
    --rebuild-android-demo)
        cd "$PROJECT_DIR" && git clean -ffdx
        cleanProject
        setupProject
        buildProject
        shift
        ;;
    --release)
        ANDROID_BUILD_TYPE="assembleRelease"
        # ANDROID_BUILD_TYPE="assembleDebug" # use this if the release apk can not be installed.
        GRADLEW_RUN_TASK="installRelease"
        changeProperty "local.properties" '^usingCMakeCompileDebug=' 's/usingCMakeCompileDebug=.*/usingCMakeCompileDebug=false/' 'usingCMakeCompileDebug=false'
        shift
        ;;
    --debug)
        ANDROID_BUILD_TYPE="assembleDebug"
        GRADLEW_RUN_TASK="installDebug"
        changeProperty "local.properties" '^usingCMakeCompileDebug=' 's/usingCMakeCompileDebug=.*/usingCMakeCompileDebug=true/' 'usingCMakeCompileDebug=true'
        shift
        ;;
    --setup-project)
        setupProject
        runGradleCommand signingReport
        exit 0 # setup then stop.
        ;;
    --clean)
        echo "clean"
        cleanProject
        shift # past argument
        ;;
    --build)
        echo "build"
        setupProject
        buildProject
        shift # past argument
        ;;
    --run)
        echo "run android demo"
        runAndroidApp
        shift # past argument
        ;;
    --enable-cmake)
        changeProperty "local.properties" '^usingCMakeCompile=' 's/usingCMakeCompile=.*/usingCMakeCompile=true/' 'usingCMakeCompile=true'
        shift # past argument
        ;;
    *)
        echo "Invalid argument $PARSE_KEY..."
        exit 1
        ;;

    esac

done

# if [[ -z "$SKIP_GRADLEW_TASKS" ]]; then

#     if [[ -n "$CLEAN_GRADLEW_TASKS" ]]; then
#         ./gradlew clean
#     fi

#     buildProject
# fi

# if [[ -n "$GRADLEW_RUN_TASK" ]] || [[ -n $SKIP_GRADLEW_TASKS ]]; then
#     runAndroidApp
# else
#     echo "apk generated at:"
#     find "$THIS_DIR/cgeDemo/build" -iname "*.apk"
# fi
