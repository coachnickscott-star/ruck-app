from PIL import Image
ap = "ios/App/App/Assets.xcassets/AppIcon.appiconset"
src = Image.open("assets/icon-only.png").convert("RGB")
p = src.load()
w, h = src.size
fill = (2, 30, 14)
stack = [(0,0),(w-1,0),(0,h-1),(w-1,h-1)]
while stack:
    x, y = stack.pop()
    if not (0 <= x < w and 0 <= y < h): continue
    if p[x,y][0] < 200: continue
    p[x,y] = fill
    stack += [(x+1,y),(x-1,y),(x,y+1),(x,y-1)]
sizes = [("AppIcon-512@2x.png",1024),("AppIcon-60x60@3x.png",180),("AppIcon-60x60@2x.png",120),("AppIcon-40x40@3x.png",120),("AppIcon-76x76@2x.png",152),("AppIcon-83.5x83.5@2x.png",167),("AppIcon-29x29@3x.png",87),("AppIcon-40x40@2x.png",80),("AppIcon-76x76@1x.png",76),("AppIcon-29x29@2x.png",58),("AppIcon-40x40@1x.png",40),("AppIcon-20x20@3x.png",60),("AppIcon-29x29@1x.png",29),("AppIcon-20x20@2x.png",40),("AppIcon-20x20@1x.png",20),("AppIcon-20x20@2x-1.png",40),("AppIcon-29x29@2x-1.png",58),("AppIcon-40x40@2x-1.png",80)]
for n, z in sizes:
    src.resize((z,z), Image.LANCZOS).save(f"{ap}/{n}", "PNG")
    print(n)
print("Done")