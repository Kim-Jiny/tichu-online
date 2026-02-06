const fs = require('fs');
const path = require('path');

const BUILD_DIR = __dirname;

// All template placeholders and their replacement values
// Sorted by key length (longest first) to prevent partial substring matches
// e.g., $short_version must be replaced before $version
const REPLACEMENTS = [
  // plist
  ['$provisioning_profile_specifier_release', ''],
  ['$provisioning_profile_specifier_debug', ''],
  ['$provisioning_profile_uuid_release', ''],
  ['$provisioning_profile_uuid_debug', ''],
  ['$pbx_launch_screen_file_reference', ''],
  ['$pbx_launch_screen_build_reference', ''],
  ['$additional_pbx_frameworks_build', ''],
  ['$additional_pbx_frameworks_refs', ''],
  ['$additional_pbx_resources_build', ''],
  ['$additional_pbx_resources_refs', ''],
  ['$pbx_launch_screen_build_phase', ''],
  ['$pbx_launch_screen_copy_files', ''],
  ['$photolibrary_usage_description', ''],
  ['$ipad_interface_orientations', '<string>UIInterfaceOrientationPortrait</string>\n\t\t<string>UIInterfaceOrientationLandscapeLeft</string>\n\t\t<string>UIInterfaceOrientationLandscapeRight</string>'],
  ['$microphone_usage_description', ''],
  ['$camera_usage_description', ''],
  ['$pbx_embeded_frameworks_build', ''],
  ['$required_device_capabilities', '<string>arm64</string>'],
  ['$code_sign_identity_release', 'Apple Development'],
  ['$launch_screen_background_color', ''],
  ['$pbx_locale_build_reference', ''],
  ['$pbx_locale_file_reference', ''],
  ['$provisioning_profile_uuid', ''],
  ['$code_sign_identity_debug', 'Apple Development'],
  ['$code_sign_style_release', 'Automatic'],
  ['$additional_plist_content', ''],
  ['$plist_launch_screen_name', '<key>UILaunchStoryboardName</key>\n\t<string>Launch Screen</string>'],
  ['$interface_orientations', '<string>UIInterfaceOrientationPortrait</string>'],
  ['$launch_screen_image_mode', ''],
  ['$pbx_embeded_frameworks', ''],
  ['$code_sign_style_debug', 'Automatic'],
  ['$targeted_device_family', '1,2'],
  ['$default_build_config', 'Debug'],
  ['$os_deployment_target', 'IPHONEOS_DEPLOYMENT_TARGET = 12.0;'],
  ['$moltenvk_buildphase', ''],
  ['$additional_pbx_files', ''],
  ['$modules_buildphase', ''],
  ['$moltenvk_buildfile', ''],
  ['$bundle_identifier', 'com.tichu.online'],
  ['$modules_buildfile', ''],
  ['$moltenvk_buildgrp', ''],
  ['$modules_buildgrp', ''],
  ['$entitlements_full', ''],
  ['$moltenvk_fileref', ''],
  ['$export_method_release', 'development'],
  ['$export_method_debug', 'development'],
  ['$modules_fileref', ''],
  ['$short_version', '1.0'],
  ['$modules_deinit', ''],
  ['$export_method', 'development'],
  ['$linker_flags', ''],
  ['$modules_decl', ''],
  ['$modules_init', ''],
  ['$docs_in_place', '<false/>'],
  ['$docs_sharing', '<false/>'],
  ['$godot_archs', 'arm64'],
  ['$valid_archs', 'arm64'],
  ['$version', '1.0'],
  ['$cpp_code', ''],
  ['$signature', '????'],
  ['$team_id', 'AWWCNFMSJ3'],
  ['$sdkroot', 'iphoneos'],
  ['$binary', 'tichu'],
  ['$name', 'Tichu Online'],
];

function replaceInFile(filePath) {
  let content;
  try {
    content = fs.readFileSync(filePath, 'utf8');
  } catch (e) {
    return;
  }

  let changed = false;
  for (const [key, val] of REPLACEMENTS) {
    if (content.includes(key)) {
      content = content.split(key).join(val);
      changed = true;
    }
  }

  if (changed) {
    fs.writeFileSync(filePath, content, 'utf8');
    console.log('  Updated:', path.relative(BUILD_DIR, filePath));
  }
}

const EXTENSIONS = new Set([
  '.pbxproj', '.plist', '.storyboard', '.entitlements',
  '.h', '.cpp', '.swift', '.m', '.mm', '.strings',
  '.xcscheme', '.xcworkspacedata',
]);

function walkDir(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === 'ios-arm64' || entry.name.endsWith('.xcframework')) continue;
      walkDir(fullPath);
    } else {
      const ext = path.extname(entry.name);
      if (EXTENSIONS.has(ext)) {
        replaceInFile(fullPath);
      }
    }
  }
}

function renameFiles() {
  const srcDir = path.join(BUILD_DIR, 'godot_apple_embedded');
  const dstDir = path.join(BUILD_DIR, 'tichu');

  if (!fs.existsSync(srcDir)) {
    console.log('  Source directory already renamed or missing');
    return;
  }

  // Rename files inside the source directory first
  const infoPlist = path.join(srcDir, 'godot_apple_embedded-Info.plist');
  if (fs.existsSync(infoPlist)) {
    fs.renameSync(infoPlist, path.join(srcDir, 'tichu-Info.plist'));
    console.log('  Renamed: godot_apple_embedded-Info.plist -> tichu-Info.plist');
  }

  const entitlements = path.join(srcDir, 'godot_apple_embedded.entitlements');
  if (fs.existsSync(entitlements)) {
    fs.renameSync(entitlements, path.join(srcDir, 'tichu.entitlements'));
    console.log('  Renamed: godot_apple_embedded.entitlements -> tichu.entitlements');
  }

  // Rename source directory
  fs.renameSync(srcDir, dstDir);
  console.log('  Renamed: godot_apple_embedded/ -> tichu/');

  // Rename scheme file
  const schemeDir = path.join(BUILD_DIR, 'godot_apple_embedded.xcodeproj', 'xcshareddata', 'xcschemes');
  const oldScheme = path.join(schemeDir, 'godot_apple_embedded.xcscheme');
  if (fs.existsSync(oldScheme)) {
    fs.renameSync(oldScheme, path.join(schemeDir, 'tichu.xcscheme'));
    console.log('  Renamed: godot_apple_embedded.xcscheme -> tichu.xcscheme');
  }

  // Rename .xcodeproj directory
  const oldProj = path.join(BUILD_DIR, 'godot_apple_embedded.xcodeproj');
  const newProj = path.join(BUILD_DIR, 'tichu.xcodeproj');
  if (fs.existsSync(oldProj)) {
    fs.renameSync(oldProj, newProj);
    console.log('  Renamed: godot_apple_embedded.xcodeproj -> tichu.xcodeproj');
  }
}

// Run
console.log('Step 1: Replacing template placeholders...');
walkDir(BUILD_DIR);

console.log('\nStep 2: Renaming files and directories...');
renameFiles();

console.log('\nDone! Open tichu.xcodeproj in Xcode.');
