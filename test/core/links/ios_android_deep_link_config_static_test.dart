import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ios Info.plist registers projectatlas custom scheme only', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(plist.contains('<key>CFBundleURLTypes</key>'), isTrue);
    expect(plist.contains('<string>projectatlas</string>'), isTrue);
    expect(
      plist.contains('<string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>'),
      isTrue,
    );

    // Must not hardcode a new bundle id or team in Info.plist during PB-2.
    expect(plist.contains('DEVELOPMENT_TEAM'), isFalse);
    expect(plist.contains('com.example.projectAtlas'), isFalse);

    // Universal Links / Associated Domains deferred.
    expect(plist.contains('com.apple.developer.associated-domains'), isFalse);

    // Flutter default deep linking disabled so app_links owns custom schemes.
    expect(plist.contains('<key>FlutterDeepLinkingEnabled</key>'), isTrue);
    expect(
      RegExp(
        r'<key>FlutterDeepLinkingEnabled</key>\s*<false/>',
      ).hasMatch(plist),
      isTrue,
    );
  });

  test('ios deployment target unchanged in pbxproj', () {
    final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(pbx.contains('IPHONEOS_DEPLOYMENT_TARGET = 13.0;'), isTrue);
    expect(pbx.contains('PRODUCT_BUNDLE_IDENTIFIER = com.example.projectAtlas;'),
        isTrue);
    expect(pbx.contains('DEVELOPMENT_TEAM'), isFalse);
  });

  test('android manifest registers projectatlas scheme without autoVerify', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest.contains('android:scheme="projectatlas"'), isTrue);
    expect(manifest.contains('android:autoVerify="true"'), isFalse);

    // Flutter default deep linking disabled so app_links owns custom schemes.
    expect(
      RegExp(
        r'android:name="flutter_deeplinking_enabled"\s*'
        r'android:value="false"',
      ).hasMatch(manifest),
      isTrue,
    );
  });
}
