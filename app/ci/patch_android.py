#!/usr/bin/env python3
"""flutter create 로 만든 android/ 에 DaySet 설정을 넣는다(CI에서 실행).

- 앱 이름 DaySet
- 홈 화면 '지금' 위젯(native/android의 코틀린·리소스·수신기)
- 권한: 인터넷(계정), 알림, 정확한 알람(기상·취침·일정 시작), 재부팅 뒤 다시 예약, 전체 화면 알람
- flutter_local_notifications 수신기(예약 알림·재부팅·알림 버튼)
- desugaring(flutter_local_notifications 요구), minSdk 24
- 서명: 빌드할 때 환경 변수 DAYSET_KEYSTORE_PATH 등이 있으면 스토어 키(AAB), 없으면 베타 키(APK, 직접 설치용).
  APK는 늘 베타 키라 이미 설치한 휴대폰에서 업데이트해도 기록이 지워지지 않는다.

여러 번 실행해도 같은 결과가 나오게 한다.
"""

import os
import re
import shutil
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else 'android'
MANIFEST = os.path.join(ROOT, 'app/src/main/AndroidManifest.xml')

PERMISSIONS = [
    'android.permission.INTERNET',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.VIBRATE',
    'android.permission.WAKE_LOCK',
    'android.permission.RECEIVE_BOOT_COMPLETED',
    'android.permission.USE_EXACT_ALARM',
    'android.permission.USE_FULL_SCREEN_INTENT',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
]
# 안드로이드 12까지는 SCHEDULE_EXACT_ALARM, 13부터는 USE_EXACT_ALARM(알람 앱)
EXTRA_PERMISSION = '<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" android:maxSdkVersion="32"/>'

RECEIVERS = '''
        <!-- flutter_local_notifications: 예약 알림, 재부팅 뒤 다시 예약, 알림 버튼 -->
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver" />
'''


NATIVE = os.path.join(os.path.dirname(ROOT) or '.', 'native', 'android')
PACKAGE_DIR = os.path.join(ROOT, 'app/src/main/kotlin/com/dayset/dayset')
WIDGET_RECEIVER = '''
        <!-- 홈 화면 '지금' 위젯 -->
        <receiver android:name=".NowWidgetProvider" android:exported="false">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data android:name="android.appwidget.provider" android:resource="@xml/now_widget_info" />
        </receiver>
'''


def copy_widget() -> None:
    """위젯 코틀린 파일과 리소스를 android/ 안으로 복사한다."""
    if not os.path.isdir(NATIVE):
        return
    os.makedirs(PACKAGE_DIR, exist_ok=True)
    kt = os.path.join(NATIVE, 'kotlin')
    for name in os.listdir(kt):
        shutil.copy(os.path.join(kt, name), os.path.join(PACKAGE_DIR, name))
    res_src = os.path.join(NATIVE, 'res')
    res_dst = os.path.join(ROOT, 'app/src/main/res')
    for folder in os.listdir(res_src):
        os.makedirs(os.path.join(res_dst, folder), exist_ok=True)
        for name in os.listdir(os.path.join(res_src, folder)):
            shutil.copy(os.path.join(res_src, folder, name), os.path.join(res_dst, folder, name))


def patch_manifest() -> None:
    s = open(MANIFEST, encoding='utf-8').read()
    s = re.sub(r'android:label="[^"]*"', 'android:label="DaySet"', s, count=1)
    lines = []
    for p in PERMISSIONS:
        if f'android:name="{p}"' not in s:
            lines.append(f'    <uses-permission android:name="{p}"/>')
    if 'android.permission.SCHEDULE_EXACT_ALARM' not in s:
        lines.append('    ' + EXTRA_PERMISSION)
    if lines:
        s = s.replace('<application', '\n'.join(lines) + '\n    <application', 1)
    if 'ScheduledNotificationReceiver' not in s:
        s = s.replace('</application>', RECEIVERS + '    </application>', 1)
    if 'NowWidgetProvider' not in s and os.path.isdir(NATIVE):
        s = s.replace('</application>', WIDGET_RECEIVER + '    </application>', 1)
    open(MANIFEST, 'w', encoding='utf-8').write(s)


SIGNING_KTS = '''
    // 스토어 키(환경 변수가 있을 때만). 없으면 베타 키(debug)로 서명한다.
    signingConfigs {
        if (System.getenv("DAYSET_KEYSTORE_PATH") != null) {
            create("store") {
                storeFile = file(System.getenv("DAYSET_KEYSTORE_PATH"))
                storePassword = System.getenv("DAYSET_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("DAYSET_KEY_ALIAS")
                keyPassword = System.getenv("DAYSET_KEY_PASSWORD")
            }
        }
    }
'''
SIGNING_GROOVY = '''
    signingConfigs {
        if (System.getenv("DAYSET_KEYSTORE_PATH") != null) {
            store {
                storeFile file(System.getenv("DAYSET_KEYSTORE_PATH"))
                storePassword System.getenv("DAYSET_KEYSTORE_PASSWORD")
                keyAlias System.getenv("DAYSET_KEY_ALIAS")
                keyPassword System.getenv("DAYSET_KEY_PASSWORD")
            }
        }
    }
'''


def patch_gradle() -> None:
    kts = os.path.join(ROOT, 'app/build.gradle.kts')
    groovy = os.path.join(ROOT, 'app/build.gradle')
    is_kts = os.path.exists(kts)
    path = kts if is_kts else groovy
    s = open(path, encoding='utf-8').read()

    if 'CoreLibraryDesugaringEnabled' not in s and 'coreLibraryDesugaringEnabled' not in s:
        flag = '        isCoreLibraryDesugaringEnabled = true\n' if is_kts else '        coreLibraryDesugaringEnabled true\n'
        if re.search(r'compileOptions\s*\{', s):
            s = re.sub(r'(compileOptions\s*\{\n)', lambda m: m.group(1) + flag, s, count=1)
        else:
            s = re.sub(r'(android\s*\{\n)', lambda m: m.group(1) + '    compileOptions {\n' + flag + '    }\n', s, count=1)

    if is_kts:
        s = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = maxOf(24, flutter.minSdkVersion)', s)
    else:
        s = re.sub(r'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion Math.max(24, flutter.minSdkVersion)', s)
        s = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = Math.max(24, flutter.minSdkVersion)', s)

    if 'desugar_jdk_libs' not in s:
        dep = 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")' if is_kts else "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'"
        s += f'\ndependencies {{\n    {dep}\n}}\n'

    if 'DAYSET_KEYSTORE_PATH' not in s:
        s = re.sub(r'(android\s*\{\n)', lambda m: m.group(1) + (SIGNING_KTS if is_kts else SIGNING_GROOVY), s, count=1)
        if is_kts:
            s = s.replace('signingConfig = signingConfigs.getByName("debug")',
                          'signingConfig = if (System.getenv("DAYSET_KEYSTORE_PATH") != null) signingConfigs.getByName("store") else signingConfigs.getByName("debug")')
        else:
            s = s.replace('signingConfig signingConfigs.debug',
                          'signingConfig System.getenv("DAYSET_KEYSTORE_PATH") != null ? signingConfigs.store : signingConfigs.debug')
    open(path, 'w', encoding='utf-8').write(s)


if __name__ == '__main__':
    copy_widget()
    patch_manifest()
    patch_gradle()
    print('android 설정을 넣었어요')
