# 刺绣 M1 检查

- `node scripts/embroidery-tests/geometry.test.cjs` 不依赖浏览器。
- `browser-smoke.cjs`、`acceptance.cjs`、`interaction.cjs` 使用 Playwright Core 和短时 `/snap/bin/chromium`，退出时关闭浏览器。
- 测试服务器在 `127.0.0.1:18039` 提供 Embroidery 网页，`/data/` 指向部署的刺绣静态资源，`/font/` 指向字体文件。本机测试驱动在 `/root/workroom/embroidery/build/test_server.py`，无生产写入端点。
- 所有作品与图像都由测试合成；不读取私聊、日记或私人相册，不向聊天发卡片。
- 浏览器依赖装在隔离的 `/root/workroom/embroidery/build/node_modules`。运行仓库内测试可设置 `NODE_PATH` 指向该目录。
- 覆盖：确定性针脚／导出、撤销重做、繁体笔顺、15 个字体入口、6 种布料×5 种形状、四角镜像、弯曲绕边、手绘一笔撤销、印花／补丁、草稿重开、窄屏尺寸。
- 此处通过不能替代 iOS 的编译、WKWebView 自定义资源协议、相册权限与键盘实机验证。
