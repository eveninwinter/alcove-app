0924 聊天字体打包进 App：这个文件夹是 Xcode 里的蓝色文件夹引用，整个复制进 bundle。
ttf 不进 git（太大），CI 构建时从 https://alcove.ob-memory.uk/api/kakao/fonts 拉下来放这里，文件名 = 字体 id.ttf。
Info.plist 的 UIAppFonts 要列 Fonts/<id>.ttf，新字体要加一行再构建；没列的照样能在 App 里点了下载。
