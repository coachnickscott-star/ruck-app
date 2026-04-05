const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

const ICON_SRC = path.join(__dirname, 'assets', 'icon-only.png');
const SPLASH_SRC = path.join(__dirname, 'assets', 'splash.png');

async function generateIcons() {
  if (!fs.existsSync(ICON_SRC)) {
    console.log('No icon source found at assets/icon-only.png, skipping icon generation');
    return;
  }

  // iOS icons
  const iosIconDir = path.join(__dirname, 'ios', 'App', 'App', 'Assets.xcassets', 'AppIcon.appiconset');
  if (fs.existsSync(iosIconDir)) {
    const iosSizes = [
      { name: 'AppIcon-20x20@1x.png', size: 20 },
      { name: 'AppIcon-20x20@2x.png', size: 40 },
      { name: 'AppIcon-20x20@2x-1.png', size: 40 },
      { name: 'AppIcon-20x20@3x.png', size: 60 },
      { name: 'AppIcon-29x29@1x.png', size: 29 },
      { name: 'AppIcon-29x29@2x.png', size: 58 },
      { name: 'AppIcon-29x29@2x-1.png', size: 58 },
      { name: 'AppIcon-29x29@3x.png', size: 87 },
      { name: 'AppIcon-40x40@1x.png', size: 40 },
      { name: 'AppIcon-40x40@2x.png', size: 80 },
      { name: 'AppIcon-40x40@2x-1.png', size: 80 },
      { name: 'AppIcon-40x40@3x.png', size: 120 },
      { name: 'AppIcon-60x60@2x.png', size: 120 },
      { name: 'AppIcon-60x60@3x.png', size: 180 },
      { name: 'AppIcon-76x76@1x.png', size: 76 },
      { name: 'AppIcon-76x76@2x.png', size: 152 },
      { name: 'AppIcon-83.5x83.5@2x.png', size: 167 },
      { name: 'AppIcon-512@2x.png', size: 1024 },
    ];
    console.log('Generating iOS icons...');
    for (const icon of iosSizes) {
      await sharp(ICON_SRC)
        .resize(icon.size, icon.size)
        .png()
        .toFile(path.join(iosIconDir, icon.name));
    }
    console.log('iOS icons generated: ' + iosSizes.length + ' sizes');
  } else {
    console.log('iOS project not found, skipping iOS icons');
  }

  // Android icons
  const androidResDir = path.join(__dirname, 'android', 'app', 'src', 'main', 'res');
  if (fs.existsSync(androidResDir)) {
    const androidSizes = [
      { dir: 'mipmap-mdpi', size: 48 },
      { dir: 'mipmap-hdpi', size: 72 },
      { dir: 'mipmap-xhdpi', size: 96 },
      { dir: 'mipmap-xxhdpi', size: 144 },
      { dir: 'mipmap-xxxhdpi', size: 192 },
    ];
    console.log('Generating Android icons...');
    for (const icon of androidSizes) {
      const dir = path.join(androidResDir, icon.dir);
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      await sharp(ICON_SRC)
        .resize(icon.size, icon.size)
        .png()
        .toFile(path.join(dir, 'ic_launcher.png'));
      await sharp(ICON_SRC)
        .resize(icon.size, icon.size)
        .png()
        .toFile(path.join(dir, 'ic_launcher_round.png'));
      // Foreground for adaptive icons
      await sharp(ICON_SRC)
        .resize(icon.size, icon.size)
        .png()
        .toFile(path.join(dir, 'ic_launcher_foreground.png'));
    }
    console.log('Android icons generated: ' + androidSizes.length + ' density buckets');
  } else {
    console.log('Android project not found, skipping Android icons');
  }
}

async function generateSplash() {
  if (!fs.existsSync(SPLASH_SRC)) {
    console.log('No splash source found at assets/splash.png, skipping splash generation');
    return;
  }

  // iOS splash - just need to replace the LaunchScreen storyboard background
  // For Capacitor, the splash is handled by the native storyboard, not image assets
  // We'll skip splash for now as it requires storyboard modification
  
  console.log('Splash screen source found. Note: Custom splash requires native storyboard changes.');
}

async function run() {
  try {
    await generateIcons();
    await generateSplash();
    console.log('Asset generation complete');
  } catch (err) {
    console.error('Asset generation error:', err.message);
  }
}

run();
