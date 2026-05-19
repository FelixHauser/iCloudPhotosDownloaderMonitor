### PhotoDownloaderMonitor

Class to keep track of iCloud photos snyc

Case:

- Have two devices open simultaneously
- On one device save a photo via SwiftData/ iCloud
- On the other device the photo should appear (that's the point of iCloud)
- It doesn't happen by magic
- This class monitors changes on swiftdata and when detected, downloads the photo
- See example file

- For certain apps, it is ok to have a loop that checks every x seconds
