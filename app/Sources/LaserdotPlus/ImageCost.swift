import AppKit

/// What a picture costs in memory (its pixels × 4 bytes), for the caches'
/// size limits (the owner's hang report showed the app at about 1 GB: the
/// caches were capped by count, whatever the pictures' sizes).
func imageCost(_ img: NSImage) -> Int {
    if let rep = img.representations.first, rep.pixelsWide > 0 {
        return rep.pixelsWide * rep.pixelsHigh * 4
    }
    return Int(img.size.width * img.size.height * 4 * 4) // points at 2× scale
}

/// A picture cache held to `megabytes` (macOS also empties it when memory
/// runs short).
func pictureCache(megabytes: Int) -> NSCache<NSString, NSImage> {
    let c = NSCache<NSString, NSImage>()
    c.totalCostLimit = megabytes << 20
    return c
}

func cachePut(_ c: NSCache<NSString, NSImage>, _ img: NSImage, _ key: NSString) {
    c.setObject(img, forKey: key, cost: imageCost(img))
}
